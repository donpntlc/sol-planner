/// Build with:
/// `flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co --dart-define=SUPABASE_ANON_KEY=eyJ...`
class SolCloudConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://goykkrdrfsysklxwdafb.supabase.co',
  );
  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    // Öffentlicher (anon) Schlüssel – Daten sind per Row Level Security pro Nutzer geschützt.
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdveWtrcmRyZnN5c2tseHdkYWZiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTUwNDMyMzQsImV4cCI6MjExMDYxOTIzNH0.8tUXg4nndK6a_CeMvhxxsbFiTEuJMWGBkvR2QxLO7eM',
  );

  static bool get isConfigured =>
      supabaseUrl.trim().isNotEmpty && supabaseAnonKey.trim().isNotEmpty;
}
