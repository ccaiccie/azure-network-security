#!/usr/bin/env python3
"""Finite direct HTTP evidence from A. No proxy/DNS or automatic retry/reconnect."""
import argparse,http.client,ipaddress,json,os,secrets,signal,socket,subprocess,threading,time
from datetime import datetime,timezone
from pathlib import Path
A='10.10.1.10';B='10.20.1.20'
def utc():return datetime.now(timezone.utc).isoformat()
def new_out(requested,case):
    out=Path(requested) if requested else Path.home()/'nva-evidence'/case
    out.parent.mkdir(parents=True,exist_ok=True)
    out.mkdir(mode=0o700,exist_ok=False) # Refuses existing directories/files/symlinks.
    return out
def identity(row,case,port,path):
    return (row.get('fixture'),row.get('case_id'),row.get('server_ip'),row.get('server_port'),row.get('peer_ip'),row.get('path'))==('azure-nva-origin-v1',case,B,port,A,path)
def perform(host,port,case,stream,duration,out,source=None):
    start=time.monotonic();frames=[];result={'started_utc':utc(),'case_id':case,'mode':'stream' if stream else 'fresh','duration_requested':duration if stream else None,'outcome':'NEEDS_REVIEW','attempted_destination':[host,port],'tcp_connect_completed':False,'request_write_status':'not-started'}
    conn=http.client.HTTPConnection(host,port,timeout=5,source_address=(source,0) if source else None)
    timer_active=threading.current_thread() is threading.main_thread()
    previous_handler=None;previous_timer=None
    if timer_active:
        def total_timeout(signum,frame):raise TimeoutError('Total bounded client window exceeded')
        previous_handler=signal.signal(signal.SIGALRM,total_timeout)
        previous_timer=signal.setitimer(signal.ITIMER_REAL,duration+10 if stream else 15)
    try:
        assert ipaddress.ip_address(host).version==4 # Literal IP, never hidden DNS/proxy.
        conn.sock=socket.socket(socket.AF_INET,socket.SOCK_STREAM)
        conn.sock.settimeout(5)
        conn.sock.bind((source or '0.0.0.0',0))
        result['attempted_local']=list(conn.sock.getsockname())
        result['client_local']=result['attempted_local']
        # Save bound source port BEFORE SYN/connect, including intentional DROP tests.
        (out/'connection.json').write_text(json.dumps(result,indent=2)+'\n')
        conn.sock.connect((host,port))
        result['tcp_connect_completed']=True;result['connected_utc']=utc()
        result['client_local']=list(conn.sock.getsockname());result['client_remote']=list(conn.sock.getpeername())
        (out/'connection.json').write_text(json.dumps(result,indent=2)+'\n')
        path=f'/stream?seconds={duration}' if stream else '/probe'
        result['request_write_status']='attempting'
        conn.request('GET',path,headers={'X-Lab-Case-ID':case,'User-Agent':f'azure-nva-lab/{case}','Connection':'close'})
        result['request_write_status']='completed-not-proof-of-delivery'
        response=conn.getresponse();result['http_status']=response.status;result['response_headers']=dict(response.getheaders())
        deadline=start+(duration+10 if stream else 15)
        with (out/'frames.ndjson').open('w') as f:
            while True:
                if time.monotonic()>deadline:raise TimeoutError('Total bounded client window exceeded')
                line=response.readline(8193)
                if not line:break
                if len(line)>8192:raise ValueError('Oversized fixture frame')
                value=json.loads(line);frames.append(value);f.write(json.dumps(value)+'\n');f.flush()
                if not stream:break
        result['frames_received']=len(frames)
        result['fixture_identity']='MATCH' if response.status==200 and frames and all(identity(x,case,port,'/stream' if stream else '/probe') for x in frames) else 'MISMATCH'
        result['last_frame_utc']=frames[-1].get('time_utc') if frames else None
        # Completeness is recorded separately; an EOF after one valid frame is not
        # a successful long-lived survival observation.
        result['stream_complete']=bool(stream and result.get('fixture_identity')=='MATCH' and frames and frames[-1].get('stream_end') is True and frames[0].get('frame')==0 and [x.get('frame') for x in frames]==list(range(len(frames))) and time.monotonic()-start>=duration-1)
    except (OSError,ValueError,http.client.HTTPException,TimeoutError) as exc:
        result['error_type']=type(exc).__name__;result['error']=str(exc);result['frames_received']=len(frames);result['stream_complete']=False
    finally:
        conn.close()
        if timer_active:
            signal.setitimer(signal.ITIMER_REAL,0);signal.signal(signal.SIGALRM,previous_handler)
            if previous_timer and previous_timer[0]>0:signal.setitimer(signal.ITIMER_REAL,*previous_timer)
        result['completed_utc']=utc();result['elapsed_seconds']=round(time.monotonic()-start,3)
        (out/'result.json').write_text(json.dumps(result,indent=2)+'\n')
    return result

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('case',choices=['positive','negative','stream']);p.add_argument('--duration',type=int,default=60);p.add_argument('--out');a=p.parse_args()
    if not 5<=a.duration<=180:p.error('duration must be5..180 seconds')
    cfg=json.loads(Path(os.environ.get('NVA_LAB_CONFIG','/etc/azure-nva-lab.json')).read_text())
    if cfg.get('role')!='app' or cfg.get('private_ip')!=A or cfg.get('backend_ip')!=B:p.error('Run only on declared app VM')
    addresses=subprocess.run(['ip','-4','-o','addr','show'],check=True,capture_output=True,text=True).stdout
    if f' {A}/' not in addresses:p.error('Expected local A address absent')
    case='nva-'+a.case+'-'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')+'-'+secrets.token_hex(4)
    try:out=new_out(a.out,case)
    except OSError as exc:p.error('Use a NEW nonexistent evidence directory: '+str(exc))
    result=perform(B,8081 if a.case=='negative' else 8080,case,a.case=='stream',a.duration,out,source=A)
    print(json.dumps(result,indent=2));print('RESULT=NEEDS_REVIEW; correlate both-node conntrack/captures, actual LB eligibility and backend journal. Evidence:',out)
if __name__=='__main__':main()
