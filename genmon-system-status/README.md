# genmon-system-status

status script for xfce4-genmon-plugin

adjust source code variables for your system, then compile and reference in the genmon widget

## advanced setup with click to refresh

- add 'Generic Monitor' to your xfce panel
- go to 'Panel Preferences...' > 'Items'
- find the line entry with the name 'Generic Monitor (external)'
- hover your mouse over it for a tooltip to display
- take note of the number proceeding genmon-.. 'Internal name: genmon-XX'
- now open the 'Properties' menu for the widget
- set the command to `sh -c 'sleep 0.05 && <path to compiled script> XX'` replacing XX with the numbers previously noted
