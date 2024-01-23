#!/bin/bash

# Ensure you have the necessary Python packages installed
pip3 install requests datetime termcolor

# Run the Python script
python3 - <<EOF
import re
import requests
from datetime import datetime
import os
import json
from time import sleep
from termcolor import colored
import os
import pymongo
import json
from json import dumps



def save_users(mongo_string):
    client = pymongo.MongoClient(mongo_string)
    db = client['api']
    users_collection = db["users"]
    cursor = users_collection.find()
    document_list = list(cursor)
    json_data = dumps(document_list)
    with open(os.path.join('users.json'), 'w') as file:
        file.write(json_data)


def get_panel_session(panel_url):
    with open('sessions.json', 'r') as f:
        sessions = json.load(f)

        if panel_url in sessions:
            return sessions[panel_url]

def get_client_data(panel_url) -> dict:
    cookie = get_panel_session(panel_url)
    try:
        header = {
            "Accept": "application/json",
            "Cookie": "; ".join([f"{k}={v}" for k, v in cookie.items()])
        }
        url = f"{format_panel_domain(panel_url)}/panel/api/inbounds/list"
        ses = requests.Session()
        response = ses.get(url, headers=header)

        data = json.loads(response.content)
        return data
    except Exception as e:
        print(colored(f"Error response: failed to get client data because {e}", "red"))



def send_file(file_path,caption_text,bot_token,chat_id):
    

    
    url = f'https://api.telegram.org/bot{bot_token}/sendDocument'
    files = {'document': open(file_path, 'rb')}
    data = {'chat_id': chat_id,'caption': caption_text}
    response = requests.post(url, files=files, data=data)
 


def send_text(text,bot_token,chat_id):
    url = 'https://api.telegram.org/bot{}/sendMessage'.format(bot_token)
    headers = {
        'Content-Type': 'application/json',
    }
    data = {
        'chat_id': chat_id,
        'text': text,
    }
    response = requests.post(url, headers=headers, json=data)   
    return response.status_code == 200




def format_panel_domain(panel_domain):
    return f'http://{panel_domain}:2053'

def days_difference_from_timestamp(timestamp):
    if timestamp == 0 or timestamp < 0:
        return 0
    dt_object = datetime.fromtimestamp(timestamp / 1000.0)
    current_datetime = datetime.now()
    time_difference = dt_object - current_datetime
    days_difference = time_difference.days
    return days_difference

def login_and_get_cookie(username, password, panel_url) -> dict:
    panel_url = format_panel_domain(panel_url)
    session = requests.Session()
    data = {"username": username, "password": password}
    url = f"{panel_url}/login"
    response = session.post(url, data=data)
    if response.status_code == 200:
        return response.cookies.get_dict()
    print(colored(f"Failed to login to {url}", "red"))
    return None

def dump_single_panel(panel_url):
    data = get_client_data(panel_url=panel_url)
    data_to_save = {}
    try:
        for obj in data['obj']:
            if obj['clientStats']:
                clients = obj['clientStats']
                for client in clients:
                    username = client['email']
                    if client['total'] == 0:
                        traffic = client['total'] - (client['down'] + client['up'])
                    else:
                        traffic = client['total'] - (client['down'] + client['up'])
                    expire_days = days_difference_from_timestamp(client['expiryTime'])
                    user_status = client['enable']
                    data_to_save[username] = {
                        'username': username,
                        'total_traffic': int(client['total'] / (1024 ** 3)),
                        'status': user_status,
                        'remaining_days': expire_days,
                        'remaining_traffic': int(traffic / (1024 ** 3)),
                    }
        for obj in data['obj']:
            settings = obj['settings']
            settings = json.loads(settings)
            for user in settings['clients']:
                email = user['email']
                user_uuid = user['id']
                data_to_save[email]['uuid'] = user_uuid
        return data_to_save
    except Exception as e:
        print(e)

def extract_urls_from_file(file_path):
    urls = []
    try:
        with open(file_path, 'r') as file:
            for line in file:
                # Using regular expression to extract URLs from each line
                url_matches = re.findall(
                    r'http[s]?://(?:[a-zA-Z]|[0-9]|[$-_@.&+]|[!*\\(\\),]|(?:%[0-9a-fA-F][0-9a-fA-F]))+', line)
                urls.extend(url_matches)
    except FileNotFoundError:
        print(colored(f"[X] File not found: {file_path}", "red"))
    except Exception as e:
        print(colored(f"[X] An error occurred: {e}", "red"))

    return urls

def main():
    print("________________________ WELCOME __________________________")
    
    file_path = input("[?] Enter the path of the text file: ")
    urls = extract_urls_from_file(file_path)

    if urls:
        print(colored("\n[✓] Stored URLs:", "green"))
        for url in urls:
            print(colored(url, "cyan"))
    else:
        print(colored("\n[X] No URLs found in the file.", "red"))

    # Prompt for username and password
    
    username = input("\n[?] Enter your username: ")
    password = input("[?] Enter your password: ")
    

    panels_sessions = {}
    print("________________________ GETTING LOGING SESSIONS FOR PANELS  __________________________")
    for panel_url in urls:
        try:
            panel_url = panel_url.split('//')[1].split(":")[0]
            print(colored('[*] Getting session for panel: {} '.format(panel_url), "yellow"))
            panels_sessions[panel_url] = login_and_get_cookie(username, password, panel_url)
            print(colored('[✓] Panel {} session saved'.format(panel_url), "green"))
            sleep(1)
        except Exception as e:
            print(colored(f"[X] Error processing panel {panel_url}: {e}", "red"))

    with open('sessions.json', 'w') as f:
        json.dump(panels_sessions, f,indent=2)
        print(colored("[✓] Sessions dumped to 'sessions.json'", "green"))

    # Ask the user if they want to backup to Telegram
    

    
    if not os.path.exists("saved_dumps"):
        os.mkdir("saved_dumps")
    print("________________________ DUMPING PANELS IN JSOMN FILE  __________________________")    
    for panel_url in urls:
        panel_url = panel_url.split("//")[1].split(":")[0]
        print(colored('[*] Dumping panel: {} users'.format(panel_url), "yellow"))
        file_name = panel_url+'.json'
        file_path = 'saved_dumps'+'/'+file_name
        with open(file_path,'w') as panel_dump_file:
            json.dump(dump_single_panel(panel_url=panel_url),panel_dump_file,indent=2)
        print(colored('[✓] Panel {} Dumped '.format(panel_url), "green"))
    backup_choice = input("\n[?] Do you want to backup to Telegram? (Enter 0 for Yes, 1 for No): ")  
    
    if backup_choice == '0':
        bot_token = input("[?] Enter your Telegram bot token: ")
        user_id = input("[?] Enter your Telegram user ID: ")

        print("________________________SENDING PANELS DUMP TO USER ID WITH TELEGRAM BOT __________________________")
        print(colored("[*] sending backups to telegram", "yellow")) 
        directory_path = 'saved_dumps'   
        for filename1 in os.listdir(directory_path):
            if os.path.isfile(os.path.join(directory_path, filename1)):
                file_path = os.path.join(directory_path, filename1)
                caption_text = filename1.split('.')[0]
                send_file(file_path, caption_text, bot_token, int(user_id))
                print(colored('[✓] Panel {} Dumped file sent to user {}'.format(panel_url,user_id), "green"))
        
    file_name = panel_url+'.json'
    file_path = 'saved_dumps'+'/'+file_name   
    mongo_string = input("[?] Enter the mongo string to get users data from it : ")
    save_users(mongo_string=mongo_string)
    all_users_dump = {}  
    print("________________________ ADDING DB TOKEN TO COLLECTED USERS__________________________")                        
    print(colored("[*] storing all users in singls file and adding token", "yellow"))   
    for panel_url in urls:
            with open(file_path,'r') as panel_dumped_file:
                for k,v in json.load(panel_dumped_file).items() :
                    all_users_dump[k] = v
                    with open('users.json','r') as f :
                        users_with_sub_and_token=json.load(f)
                    for user in users_with_sub_and_token:
                        if k==user['_id']:
                            
                            all_users_dump[k]['token'] = user['token']
    
    with open('all_users_dump.json','w') as all_users :
        
        json.dump(all_users_dump,all_users,indent=2)
        print(colored('[✓] all users dumped ', "green"))  
    if backup_choice == '0':     
        print(colored("[*] sending all users dump with sub token to telegram bot", "yellow"))      
        send_file('all_users_dump.json', caption_text, bot_token, int(user_id)) 
        print(colored('[✓] all users dump sent to user {}'.format(user_id), "green"))      
if __name__ == "__main__":
    main()




EOF
