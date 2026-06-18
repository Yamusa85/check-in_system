# check-in_system
Python web check-in system for mini conventions

<img width="2426" height="1467" alt="image" src="https://github.com/user-attachments/assets/b33c6587-a1d4-419e-9aaa-957d677e2656" />


Simple and quite functional web system for receptionists at your mini conventions to check-in your guests.

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

Place checkin-system in home dir or anywhere, start app.py
