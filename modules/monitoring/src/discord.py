import json
import os
import urllib3

http = urllib3.PoolManager()
URL = os.environ.get('DISCORD_WEBHOOK_URL') 

def lambda_handler(event, context):
    if not URL:
        print("Error: DISCORD_WEBHOOK_URL is not set.")
        return

    try:
        # SNS 메시지 추출
        sns_message = event['Records'][0]['Sns']['Message']
        
        try:
            # 알람 JSON 파싱
            data = json.loads(sns_message)
            alarm_name = data.get('AlarmName', 'Unknown')
            state = data.get('NewStateValue', 'UNKNOWN')
            reason = data.get('NewStateReason', 'No reason')
            
            color = 16711680 if state == 'ALARM' else 65280 
            payload = {
                "embeds": [{
                    "title": f"🚨 {alarm_name}",
                    "description": reason,
                    "color": color,
                    "fields": [{"name": "State", "value": state, "inline": True}]
                }]
            }
        except Exception:
            # 일반 텍스트 메시지일 경우
            payload = {"content": f"📢 **Notification:**\n{sns_message}"}

        # 디스크로드 전송
        encoded_data = json.dumps(payload).encode('utf-8')
        res = http.request('POST', URL, body=encoded_data, headers={'Content-Type': 'application/json'})
        print(f"Response Status: {res.status}")
        
    except Exception as e:
        print(f"Error: {e}")