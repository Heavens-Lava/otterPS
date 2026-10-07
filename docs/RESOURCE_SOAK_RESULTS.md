# Otter 1.0 - Memory & Resource Soak Report

## Test Environment
- **Host**: Windows PowerShell 5.1
- **Date**: 2026-09-30 07:50:15

## Soak Workload Results

| Workload | Iterations | Start (MB) | Mid (MB) | End (MB) | Net Delta (MB) | Mid-End Delta (MB) | Status | Duration (s) |
|---|---|---|---|---|---|---|---|---|
| 1. Parse 1,000x | 1000 | 109.96 | 135.95 | 146.07 | 36.11 | 10.12 | **STABLE** | 21.13s |
| 2. Execute Program 1,000x | 1000 | 132.16 | 149.91 | 146.48 | 14.32 | -3.43 | **STABLE** | 9.95s |
| 3. Web Compile 200x | 200 | 146.56 | 175.52 | 193.53 | 46.97 | 18.01 | **STABLE** | 1.64s |
| 4. File Read/Write 500x | 500 | 193.53 | 173.5 | 176.63 | -16.9 | 3.13 | **STABLE** | 6.76s |
| 5. Run Command 50x | 50 | 176.68 | 183.41 | 175.4 | -1.28 | -8.01 | **STABLE** | 8s |
| 6. JSON Convert 500x | 500 | 175.42 | 190.91 | 197.9 | 22.48 | 6.99 | **STABLE** | 1.51s |
| 7. Function Calls 5,000x | 5000 | 180.5 | 184.05 | 181.23 | 0.73 | -2.82 | **STABLE** | 6.12s |
| 8. Failures & Diagnostics 500x | 500 | 181.23 | 185.69 | 199.44 | 18.21 | 13.75 | **STABLE** | 3.16s |

Status: STABLE means private memory grew by at most 25 MB between the middle and the end of the workload; INVESTIGATE otherwise.

## Measured leak checks
- **Files left in the soak folder by the workloads**: 0
- **Child processes still running after the workloads**: 0
- **Handles held by this process**: 854 before, 807 after (change -47)

## Review (2026-09-30, rc.8 `16a2e88` source)

- All eight workloads are STABLE, and the three measured leak checks are clean: no files left behind, no child processes left running, and the process holds fewer handles afterwards than before.
- Web compile is the one workload that keeps growing through its second half: 16.6, 17.2 and 18.0 MB mid-to-end across three runs of 200 compiles. It is under the 25 MB bar but consistent, so it is worth a longer run (for example 2,000 compiles) before 1.0.0 to tell a slow leak from caches warming up. Studio and `otter serve` compile repeatedly in one process; a single `otter web` does not.
- Before this review the report also listed "leak inspection" results (AST references, call stacks, file handles, temporary files, child processes) that the script printed without measuring. Those lines are gone; only measured checks are reported.
