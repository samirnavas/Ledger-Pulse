class SupabaseConfig {
  static const String url = 'https://awzxwsmfyrbnnuqkxuxu.supabase.co';
  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF3enh3c21meXJibm51cWt4dXh1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAxNzkyNzQsImV4cCI6MjEwNTc1NTI3NH0.v0awSgnhtbCLEOPGwbh8jpky_C1uRTRT5x5gL3AHlbo';
  static const String publishableKey = anonKey;

  static bool get isConfigured =>
      url.isNotEmpty &&
      anonKey.isNotEmpty &&
      !url.contains('mock') &&
      !anonKey.contains('mock');
}
