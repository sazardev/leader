<!-- name: Dashboards and reports -->
<!-- desc: numbers people check often: totals, trends, periods, export of a report -->
<!-- for: all -->
<!-- tech: database jobs -->
<!-- design: dashboards-charts -->

## Requirements

### Dashboard

The system must show the numbers that matter at a glance, with their period.

- Given a person who opens the dashboard, when it loads, then they see the main figures and the period they cover
- Given a period picked by the person, when it changes, then every figure and chart changes with it

### Reports

The system must let a person get a detailed report and take it away.

- Given a report with filters, when a person runs it, then it shows what matches and how long ago the data was updated
- Given a report, when a person exports it, then the file has exactly what they saw

## Edge cases

- [Dashboard] No data in the period: the dashboard says so instead of showing zeros that look like results
- [Reports] A report too big to show at once is produced in the background and the person is told when it is ready
- [Dashboard] Figures that depend on a time zone are cut at the person's midnight, not the server's

## Open questions

- [Dashboard] Which figures decide whether the product works, and how fresh must they be?
- [Reports] Who can see which reports, and can they be scheduled by email?
