Read {{PROJECT_DIR}}/workspace/ESCALATE.txt and {{PROJECT_DIR}}/workspace/tasks.json. Review the escalation and determine which task triggered it.

1. Read the escalation details and the current task state
2. Provide reasonable review feedback in the relevant task's summary file ({{PROJECT_DIR}}/workspace/{task_id}/{task_id}_summary.md)
3. Mark the task as `passes: true` in {{PROJECT_DIR}}/workspace/tasks.json
4. Append to {{PROJECT_DIR}}/workspace/progress.md with Status: PASS (auto-reviewed) and a brief rationale
5. Delete {{PROJECT_DIR}}/workspace/ESCALATE.txt
6. Git commit with message: "Auto-review {task_id}: escalation resolved in unattended mode"
