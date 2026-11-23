# check-in_system
Python web check-in system for mini conventions  (Disclaimer: created with the help of AI agent)

:warning:ATTENTION:warning: Not for online use, use in local network only! 

Admin interface:
<img width="2302" height="993" alt="image" src="https://github.com/user-attachments/assets/67f66ce9-3ea8-4662-9f52-eb3bc54e27e0" />

Manager interface:
<img width="3767" height="1764" alt="Screenshot 2026-11-22 101836" src="https://github.com/user-attachments/assets/7b5d2845-1969-47aa-b1fe-977d2cfd3584" />

Seats map page:
<img width="1893" height="874" alt="image" src="https://github.com/user-attachments/assets/bb4b90ff-db35-4205-8f80-7bc5328d0541" />




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
1) sqlite3
2) python3
3) python3-flask
4) python3-flask-login
5) python3-werkzeug
6) python3-pandas
7) python3-openpyxl

for Ubuntu install

```copy
curl -O https://raw.githubusercontent.com/Yamusa85/check-in_system/refs/heads/main/install-checkin.sh
```
```copy
bash install-checkin.sh
```

Optional:
1) NGINX with LE-cert and proxying
2) add app.py into systemd launch

Place "checkin-system" folder and its contents in home dir or anywhere, start app.py
