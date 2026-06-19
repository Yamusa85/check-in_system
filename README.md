# check-in_system
Python web check-in system for mini conventions  (Disclaimer: created with the help of AI agent)

Admin interface:
<img width="2302" height="993" alt="image" src="https://github.com/user-attachments/assets/67f66ce9-3ea8-4662-9f52-eb3bc54e27e0" />

Manager interface:
<img width="2426" height="1467" alt="image" src="https://github.com/user-attachments/assets/b33c6587-a1d4-419e-9aaa-957d677e2656" />


Simple and quite functional web system for receptionists at your mini conventions to check-in your guests.
May be used online or in your local network.

Site available at http://serveraddress:5000

Default logopasses: admin/admin123, manager/manager123  (may be changed in app.py)

Functionality:
1) import guests list from excel file
2) 2 necessary and unlimited optional columns for your data
3) 2 accounts: admin and manager
4) simple and intuitive interface
5) managers have options to export results, filter current list of guests, edit guests data on the go

Requirements (linux):
1) sqlite
2) python3
3) python3-flask
4) python3-flask-login
5) python3-werkzeug
6) python3-pandas
7) python3-openpyxl

Optional:
1) NGINX with LE-cert and proxying
2) add app.py into systemd launch

Place "checkin-system" folder and its contents in home dir or anywhere, start app.py
