#ifndef TINYSTAT_AGENT_PROCESS_H
#define TINYSTAT_AGENT_PROCESS_H
#include <stddef.h>
// A job owns a POSIX process group and two nonblocking pipe descriptors.
int ts_agent_spawn(const char *path, char *const argv[], char *const env[], const char *cwd, int *input, int *output);
int ts_agent_read(int fd, void *bytes, int capacity);
int ts_agent_write(int fd, const void *bytes, int count);
int ts_agent_poll(int pid, int *status);
void ts_agent_signal(int pid, int signal_number);
#endif
