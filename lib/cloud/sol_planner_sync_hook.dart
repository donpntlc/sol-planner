/// Called after planner-relevant data was written to [SharedPreferences].
void Function()? solOnPlannerDiskDataChanged;

void solNotifyPlannerDiskDataChanged() {
  solOnPlannerDiskDataChanged?.call();
}
