/// SharedPreferences keys that are synced to Supabase (must match main.dart / reminder prefs).

/// Meta: last remote [updated_at] we fully applied locally (ISO 8601 UTC).
const String kSolCloudLastAppliedRemoteAtKey = 'sol_cloud_last_applied_remote_at';

/// User enabled background sync (push + pull on resume).
const String kSolCloudSyncEnabledPrefKey = 'sol_cloud_sync_enabled_v1';

const String kPlannerReminderPrefsKeySync = 'planner_reminder_prefs_v1';

const List<String> kSolSyncedPlannerStringPrefKeys = [
  'planner_category_colors_v2',
  'planner_category_catalog_v1',
  'planner_preset_task_templates_v1',
  'planner_user_preset_days_v1',
  'planner_day_freeform_notes_v1',
  'planner_cached_days_v1',
  'planner_custom_stripe_swatches_v1',
  'planner_custom_category_swatches_v1',
  'planner_subtask_quick_presets_v1',
  'planner_builtin_preset_display_names_v1',
  'planner_project_rotation_v1',
  kPlannerReminderPrefsKeySync,
];
