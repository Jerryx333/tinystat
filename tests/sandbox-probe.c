// Probe production Seatbelt rules with synthetic files and loopback addresses.
// Built and run by scripts/verify-sandbox.py; no user files are read.
// Requires macOS clang and execution inside AgentSandbox.
#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/wait.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <arpa/inet.h>
#include <errno.h>
#include <string.h>
static int deniedExec(const char *path){pid_t p=fork();if(p<0)return 0;if(!p){execl(path,path,"-h",NULL);_exit(errno==EPERM||errno==EACCES ? 42:43);}int s;return waitpid(p,&s,0)==p&&WIFEXITED(s)&&WEXITSTATUS(s)==42;}
static int shellExit(const char *script,const char *path){pid_t p=fork();if(p<0)return -1;if(!p){execl("/bin/sh","sh","-c",script,"probe",path,NULL);_exit(43);}int s;return waitpid(p,&s,0)==p&&WIFEXITED(s) ? WEXITSTATUS(s):-1;}
int main(int argc,char **argv){
    if(argc==2&&!strcmp(argv[1],"--deny-exec"))return deniedExec("/bin/zsh") ? 0:1;
    if(argc!=5)return 64;
    int fd=open(argv[1],O_RDONLY);if(fd>=0){close(fd);return 10;}
    fd=open(argv[1],O_WRONLY);if(fd>=0){close(fd);return 11;}
    if(link(argv[1],argv[2])==0)return 17;
    fd=open(argv[2],O_WRONLY|O_CREAT,0600);if(fd<0)return 12;close(fd);
    if(strcmp(argv[3],"login") && (!deniedExec("/bin/sh") || !deniedExec("/bin/bash")))return 14;
    if(!deniedExec("/bin/zsh")||!deniedExec("/bin/dash")||!deniedExec("/usr/bin/env"))return 22;
    if(!strcmp(argv[3],"login")){
        if(shellExit("exit 0",argv[1])!=0)return 23;
        if(shellExit("exec < \"$1\"",argv[1])!=1)return 24;
        if(shellExit("exec > \"$1\"",argv[1])!=1)return 25;
        if(shellExit("exec \"$1\" --deny-exec",argv[0])!=0)return 26;
    }
    if(strcmp(argv[3],"login")&& !deniedExec("/usr/bin/security"))return 18;
    const char *ips[]={"127.0.0.1","127.0.0.2","0.0.0.0","::1","::ffff:127.0.0.1"};
    for(int i=0;i<5;i++){
        int family=i<3?AF_INET:AF_INET6,sock=socket(family,SOCK_STREAM,0);if(sock<0)return 15;fcntl(sock,F_SETFL,O_NONBLOCK);
        struct sockaddr_in a={.sin_len=sizeof(a),.sin_family=AF_INET,.sin_port=htons(9)};
        struct sockaddr_in6 b={.sin6_len=sizeof(b),.sin6_family=AF_INET6,.sin6_port=htons(9)};
        inet_pton(family,ips[i],i<3?(void*)&a.sin_addr:(void*)&b.sin6_addr);
        int r=connect(sock,i<3?(struct sockaddr*)&a:(struct sockaddr*)&b,i<3?sizeof(a):sizeof(b)),err=errno;close(sock);
        if(r==0||(err!=EPERM&&err!=EACCES)){if(i==0||i==3){fprintf(stderr,"localhost probe failed: %s errno %d\n",ips[i],err);return 16;}printf("LIMITATION: address alias %s is not blocked by Seatbelt localhost filter\n",ips[i]);}
    }
    int sock=socket(AF_UNIX,SOCK_STREAM,0);if(sock<0)return 19;
    struct sockaddr_un un={.sun_len=sizeof(un),.sun_family=AF_UNIX};if(strlen(argv[4])>=sizeof(un.sun_path))return 21;strcpy(un.sun_path,argv[4]);
    int r=connect(sock,(struct sockaddr*)&un,sizeof(un)),err=errno;close(sock);if(r==0||(err!=EPERM&&err!=EACCES))return 20;
    printf("PASS: outside read/write/hardlink, localhost, Unix socket and unlisted exec denied; scratch write allowed; shell %s\n",strcmp(argv[3],"login") ? "denied":"startup and inherited restrictions verified");return 0;
}
