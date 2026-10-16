// Spawn and supervise one CLI process group, without an intermediate shell.
// Built by scripts/build.sh; requires macOS POSIX APIs.
#include "AgentProcess.h"
#include <spawn.h>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>
#include <sys/wait.h>
#include <errno.h>
int ts_agent_spawn(const char *path,char *const argv[],char *const env[],const char *cwd,int *input,int *output) {
    int in[2],out[2];if(pipe(in))return -errno;
    if(pipe(out)){int e=errno;close(in[0]);close(in[1]);return -e;}
    for(int i=0;i<2;i++){fcntl(in[i],F_SETFD,FD_CLOEXEC);fcntl(out[i],F_SETFD,FD_CLOEXEC);}
    posix_spawn_file_actions_t actions;posix_spawnattr_t attr;
    posix_spawn_file_actions_init(&actions);posix_spawnattr_init(&attr);
    int e=posix_spawn_file_actions_addchdir_np(&actions,cwd);
    if(!e)e=posix_spawn_file_actions_adddup2(&actions,in[0],STDIN_FILENO);
    if(!e)e=posix_spawn_file_actions_adddup2(&actions,out[1],STDOUT_FILENO);
    if(!e)e=posix_spawn_file_actions_addopen(&actions,STDERR_FILENO,"/dev/null",O_WRONLY,0);
    sigset_t mask,defaults;sigemptyset(&mask);sigfillset(&defaults);
    if(!e)e=posix_spawnattr_setsigmask(&attr,&mask);
    if(!e)e=posix_spawnattr_setsigdefault(&attr,&defaults);
    if(!e)e=posix_spawnattr_setflags(&attr,POSIX_SPAWN_SETPGROUP|POSIX_SPAWN_CLOEXEC_DEFAULT|POSIX_SPAWN_SETSIGMASK|POSIX_SPAWN_SETSIGDEF);
    if(!e)e=posix_spawnattr_setpgroup(&attr,0);
    pid_t pid=0;if(!e)e=posix_spawn(&pid,path,&actions,&attr,argv,env);
    posix_spawn_file_actions_destroy(&actions);posix_spawnattr_destroy(&attr);close(in[0]);close(out[1]);
    if(e){close(in[1]);close(out[0]);return -e;}
    fcntl(in[1],F_SETFL,O_NONBLOCK);fcntl(out[0],F_SETFL,O_NONBLOCK);
    *input=in[1];*output=out[0];return pid;
}
int ts_agent_read(int fd,void *bytes,int capacity) {ssize_t n=read(fd,bytes,(size_t)capacity);return n<0 ? -errno:(int)n;}
int ts_agent_write(int fd,const void *bytes,int count) {ssize_t n=write(fd,bytes,(size_t)count);return n<0 ? -errno:(int)n;}
int ts_agent_poll(int pid,int *status) {
    siginfo_t info={0};
    if(waitid(P_PID,(id_t)pid,&info,WEXITED|WNOHANG|WNOWAIT)<0)return -errno;
    if(!info.si_pid)return 0;
    // The unreaped leader reserves its PID/group identity until cleanup is signalled.
    kill(-pid,SIGKILL);
    int raw=0;pid_t r;do{r=waitpid(pid,&raw,0);}while(r<0 && errno==EINTR);
    if(r<0)return -errno;
    *status=WIFEXITED(raw)?WEXITSTATUS(raw):128+(WIFSIGNALED(raw)?WTERMSIG(raw):0);return 1;
}
void ts_agent_signal(int pid,int number) {if(pid>1)kill(-pid,number);}
