const http = require('http');
const fs = require('fs');
const path = require('path');
const url = require('url');

const PORT = process.env.PORT || 3000;
const DATA_FILE = path.join(__dirname, 'data.json');

// Helper to read data from data.json
function readData() {
  try {
    if (!fs.existsSync(DATA_FILE)) {
      return { parties: [], entries: [] };
    }
    const raw = fs.readFileSync(DATA_FILE, 'utf-8');
    return JSON.parse(raw);
  } catch (err) {
    console.error('Error reading data.json:', err);
    return { parties: [], entries: [] };
  }
}

// Helper to atomically save data to data.json
function saveData(data) {
  try {
    const tempFile = `${DATA_FILE}.tmp`;
    fs.writeFileSync(tempFile, JSON.stringify(data, null, 2), 'utf-8');
    fs.renameSync(tempFile, DATA_FILE);
  } catch (err) {
    console.error('Error saving data.json:', err);
    throw err;
  }
}

// Recalculate party balance and lastUpdated timestamp from its entries
function recalculateParty(partyId, data) {
  const party = data.parties.find(p => p.id === partyId);
  if (!party) return;

  const partyEntries = data.entries.filter(e => e.partyId === partyId);
  let balance = 0;
  let latestDate = party.lastUpdated ? new Date(party.lastUpdated) : new Date(0);

  for (const entry of partyEntries) {
    if (entry.type === 'gave') {
      balance += Number(entry.amountInCents) || 0;
    } else {
      balance -= Number(entry.amountInCents) || 0;
    }
    const entryDate = new Date(entry.date);
    if (entryDate > latestDate) {
      latestDate = entryDate;
    }
  }

  party.netBalanceInCents = balance;
  party.lastUpdated = latestDate.toISOString();
}

// Parse request body JSON
function parseRequestBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', chunk => {
      body += chunk.toString();
    });
    req.on('end', () => {
      if (!body.trim()) {
        return resolve({});
      }
      try {
        resolve(JSON.parse(body));
      } catch (err) {
        reject(new Error('Invalid JSON body'));
      }
    });
    req.on('error', reject);
  });
}

// Send JSON response with CORS headers
function sendJson(res, statusCode, payload) {
  res.writeHead(statusCode, {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  });
  res.end(JSON.stringify(payload));
}

const server = http.createServer(async (req, res) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    });
    return res.end();
  }

  const parsedUrl = url.parse(req.url, true);
  const pathname = parsedUrl.pathname;
  const method = req.method;

  try {
    // GET /api/summary
    if (method === 'GET' && pathname === '/api/summary') {
      const data = readData();
      let totalReceivable = 0;
      let totalPayable = 0;

      for (const party of data.parties) {
        if (party.netBalanceInCents > 0) {
          totalReceivable += party.netBalanceInCents;
        } else if (party.netBalanceInCents < 0) {
          totalPayable += Math.abs(party.netBalanceInCents);
        }
      }

      return sendJson(res, 200, { totalReceivable, totalPayable });
    }

    // GET /api/parties (with optional ?type=customer|supplier)
    if (method === 'GET' && pathname === '/api/parties') {
      const data = readData();
      const typeFilter = parsedUrl.query.type;
      let result = data.parties;
      if (typeFilter) {
        result = result.filter(p => p.type === typeFilter);
      }
      return sendJson(res, 200, result);
    }

    // POST /api/parties
    if (method === 'POST' && pathname === '/api/parties') {
      const body = await parseRequestBody(req);
      if (!body.id || !body.name || !body.phoneNumber || !body.type) {
        return sendJson(res, 400, { error: 'Missing required party fields' });
      }

      const data = readData();
      const existingIndex = data.parties.findIndex(p => p.id === body.id);
      const party = {
        id: body.id,
        name: body.name,
        phoneNumber: body.phoneNumber,
        type: body.type,
        netBalanceInCents: Number(body.netBalanceInCents) || 0,
        lastUpdated: body.lastUpdated || new Date().toISOString(),
      };

      if (existingIndex >= 0) {
        data.parties[existingIndex] = party;
      } else {
        data.parties.unshift(party);
      }

      saveData(data);
      return sendJson(res, 201, party);
    }

    // GET /api/parties/:id
    const singlePartyMatch = pathname.match(/^\/api\/parties\/([a-zA-Z0-9_\-]+)$/);
    if (method === 'GET' && singlePartyMatch) {
      const partyId = singlePartyMatch[1];
      const data = readData();
      const party = data.parties.find(p => p.id === partyId);
      if (!party) {
        return sendJson(res, 404, { error: 'Party not found' });
      }
      return sendJson(res, 200, party);
    }

    // GET /api/parties/:id/entries
    const partyEntriesMatch = pathname.match(/^\/api\/parties\/([a-zA-Z0-9_\-]+)\/entries$/);
    if (method === 'GET' && partyEntriesMatch) {
      const partyId = partyEntriesMatch[1];
      const data = readData();
      const partyEntries = data.entries.filter(e => e.partyId === partyId);

      // Sort ascending to compute running balances
      partyEntries.sort((a, b) => new Date(a.date) - new Date(b.date));

      let currentBalance = 0;
      const entriesWithRunningBalance = partyEntries.map(entry => {
        if (entry.type === 'gave') {
          currentBalance += Number(entry.amountInCents) || 0;
        } else {
          currentBalance -= Number(entry.amountInCents) || 0;
        }
        return {
          ...entry,
          runningBalanceInCents: currentBalance,
        };
      });

      // Sort descending (newest first) for UI timeline
      entriesWithRunningBalance.sort((a, b) => new Date(b.date) - new Date(a.date));
      return sendJson(res, 200, entriesWithRunningBalance);
    }

    // POST /api/entries
    if (method === 'POST' && pathname === '/api/entries') {
      const body = await parseRequestBody(req);
      if (!body.id || !body.partyId || body.amountInCents == null || !body.type || !body.date) {
        return sendJson(res, 400, { error: 'Missing required entry fields' });
      }

      const data = readData();
      const newEntry = {
        id: body.id,
        partyId: body.partyId,
        amountInCents: Number(body.amountInCents),
        type: body.type,
        date: body.date,
        note: body.note || null,
        receiptPhotoUrl: body.receiptPhotoUrl || null,
      };

      data.entries.push(newEntry);
      recalculateParty(newEntry.partyId, data);
      saveData(data);

      return sendJson(res, 201, newEntry);
    }

    // DELETE /api/entries/:id
    const deleteEntryMatch = pathname.match(/^\/api\/entries\/([a-zA-Z0-9_\-]+)$/);
    if (method === 'DELETE' && deleteEntryMatch) {
      const entryId = deleteEntryMatch[1];
      const data = readData();
      const index = data.entries.findIndex(e => e.id === entryId);
      if (index === -1) {
        return sendJson(res, 404, { error: 'Entry not found' });
      }

      const partyId = data.entries[index].partyId;
      data.entries.splice(index, 1);
      recalculateParty(partyId, data);
      saveData(data);

      return sendJson(res, 200, { success: true, deletedId: entryId });
    }

    // Route not found
    return sendJson(res, 404, { error: 'Endpoint not found' });
  } catch (err) {
    console.error('Server error handling request:', err);
    return sendJson(res, 500, { error: 'Internal Server Error', message: err.message });
  }
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`========================================`);
  console.log(` LedgerPulse JSON Server is running!`);
  console.log(` Port: ${PORT}`);
  console.log(` Local: http://localhost:${PORT}`);
  console.log(` Android Emulator: http://10.0.2.2:${PORT}`);
  console.log(` Database: ${DATA_FILE}`);
  console.log(`========================================`);
});
