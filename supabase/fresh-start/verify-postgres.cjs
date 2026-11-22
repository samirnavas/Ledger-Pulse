const fs = require('node:fs/promises');
const path = require('node:path');

async function verify(packageDirectory) {
  if (!packageDirectory) {
    throw new Error('Pass the path to the installed @electric-sql/pglite package.');
  }
  const { PGlite } = require(path.resolve(packageDirectory));
  const database = new PGlite();
  const project = path.join(__dirname, 'supabase');

  try {
    // Supabase contract fixture. The verifier never opens a network connection
    // or accepts a database URL.
    await database.exec(`
      create role anon;
      create role authenticated;
      create schema auth;
      create table auth.users (
        id uuid primary key,
        email text,
        raw_user_meta_data jsonb default '{}'
      );
      create function auth.uid() returns uuid language sql stable as $$
        select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid
      $$;
      grant usage on schema auth to authenticated, anon;
      create schema storage;
      create table storage.buckets (id text primary key, name text, public boolean);
      create table storage.objects (
        bucket_id text references storage.buckets(id),
        name text,
        unique (bucket_id,name)
      );
      alter table storage.objects enable row level security;
      grant usage on schema storage to authenticated, anon;
      grant select, insert, update, delete on storage.objects to authenticated;
    `);
    const startingRows = await database.query('select count(*)::int as total from auth.users');
    if (startingRows.rows[0].total !== 0) throw new Error('Expected an empty Auth fixture.');
    const migrations = path.join(project, 'migrations');
    const files = (await fs.readdir(migrations)).filter(name => name.endsWith('.sql')).sort();
    const sources = await Promise.all(files.map(file => fs.readFile(path.join(migrations, file), 'utf8')));
    await verifyCutoverTransaction(database, sources);
    for (const [index, file] of files.entries()) {
      await database.exec(sources[index]);
      console.log('Applied', file);
    }

    const contract = await fs.readFile(path.join(project, 'tests', 'ledgerpulse_database.test.sql'), 'utf8');
    const results = await database.exec(contract.replace(/ \\gset/g, ';'));
    const assertions = results.flatMap(result => result.rows).flatMap(row => Object.values(row));
    if (!assertions.includes('ok 1 - LedgerPulse database contract')) {
      throw new Error('Database contract did not complete.');
    }
    const remaining = await database.query('select count(*)::int as total from auth.users');
    if (remaining.rows[0].total !== 0) throw new Error('Fixture records remained after rollback.');
    const version = await database.query('show server_version');
    console.log('PostgreSQL', version.rows[0].server_version, 'Database contract passed.');
  } finally {
    await database.close();
  }
}

async function verifyCutoverTransaction(database, sources) {
  const userId = '10000000-0000-4000-8000-000000000099';
  await database.exec(`
    create table public.user_profiles (id uuid primary key references auth.users(id));
    insert into auth.users (id) values ('${userId}');
    insert into public.user_profiles (id) values ('${userId}');
  `);
  await database.exec(`
    begin;
    drop table public.user_profiles restrict;
  `);
  for (const source of sources) {
    if (!/^begin;\s/i.test(source) || !/\ncommit;\s*$/i.test(source)) {
      throw new Error('Expected outer transaction delimiters in the migration.');
    }
    await database.exec(source.replace(/^begin;\s/i, '').replace(/\ncommit;\s*$/i, ''));
  }
  const normalized = await database.query('select id from public.users');
  if (normalized.rows.length !== 1 || normalized.rows[0].id !== userId) {
    throw new Error('Cutover did not seed the existing Auth identity.');
  }
  await database.exec('rollback');
  const restored = await database.query(`
    select (select id from auth.users) as auth_id,
           (select id from public.user_profiles) as legacy_id,
           to_regclass('public.users') as normalized_table
  `);
  if (restored.rows[0].auth_id !== userId || restored.rows[0].legacy_id !== userId ||
      restored.rows[0].normalized_table !== null) {
    throw new Error('Cutover rollback did not restore the legacy fixture and preserve Auth.');
  }
  await database.exec('drop table public.user_profiles; delete from auth.users;');
  console.log('Atomic cutover rollback and Auth preservation passed against the minimal legacy fixture.');
}

verify(process.argv[2]).catch(error => {
  console.error(error.message);
  if (error.where) console.error(error.where);
  process.exitCode = 1;
});
