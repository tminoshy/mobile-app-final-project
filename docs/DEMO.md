# Class demo and acceptance checklist

Use three registered users (Alice, Bob, Cara) and at least two emulator sessions. Keep the server running and verify its health first.

1. Launch offline as Guest. Create a Food category/bucket with a $50 monthly target. Record a $40 dinner and find it through History search and category/date filters. Confirm the 80% alert appears once. Add $10.01 and confirm the over-target alert. Restart and verify records remain.
2. Rename a category, both keeping and moving existing records. Delete a category with a replacement, then delete a bucket. Confirm reports/history retain entries and their updated categorization.
3. Register Alice with guest records and verify the merge. On another device, sign in and choose Merge, then separately test Use online data with the warning and a failed download. Guest records must remain until a complete download succeeds.
4. Change an entry offline from $40 to $45. Reconnect and inspect the second device. Change the same entry online first, then reconnect the offline device: online wins. Delete while another device has an older edit: the entry must not return. Retry a timed-out batch and verify no duplicates.
5. Alice creates a group and invites Bob and Cara using a code. Record a $120 bill paid by Alice, equally split three ways. Confirm $40 per person, Alice owed $80, and personal spending includes only each person’s share. Test an exact split and a non-divisible-cent equal split.
6. Bob records a $40 repayment to Alice. Pending must not change balances. Alice confirms: Bob owes $0 and Cara still owes $40. Reports must not count repayment. Request and approve a reversal; also test rejection and cancelling a pending repayment.
7. The expense creator proposes $120 → $150 with a reason. Review old/new shares, approve on the required accounts, and verify balances and personal entries update. Test a rejection with a note, withdrawal, and no-response status. A second pending correction must be rejected by the server. Review append-only correction/activity history.
8. Promote/demote an admin, transfer ownership, revoke an invitation, and test an expired code. Try leaving with a balance or pending action, then settle and leave. Verify the snapshot is read-only. Close as owner after eligibility checks. Remove from My groups, sync, then delete the retained shared personal entry.
9. Open notifications, mark one/all read, and follow links to exact expense/correction/repayment records. Verify local alerts for a guest. Deny Android permission and confirm in-app notifications still work.
10. Sign out when synced, then with an unsynced record and the explicit loss checkbox. Confirm tokens/caches/records clear and a new guest workspace opens. Verify session expiry retains local data and permits re-login.

The live backend and device steps were not executable in the restricted implementation environment. Record results and screenshots before marking these checks passed.
