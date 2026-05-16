/// Supabase connection config.
/// The anon key is *designed* to be public — RLS on the server protects data.
/// Values can be overridden at build time with --dart-define for staging vs prod:
///
///   flutter run \
///     --dart-define=SUPABASE_URL=https://YOUR.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=eyJ...
///
/// The defaults below point at the linked Minto project.
class SupabaseConfig {
  SupabaseConfig._();

  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://ulojulpdlleisymszamf.supabase.co',
  );

  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVsb2p1bHBkbGxlaXN5bXN6YW1mIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg4ODQxNDAsImV4cCI6MjA5NDQ2MDE0MH0.8advfSbwBxTsuuvk3-UKxCJ9eu4q6urd8KF5_8bBjys',
  );
}
