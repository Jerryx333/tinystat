// Synthetic sibling process for identity-gated SIGTERM validation only.
// Run through scripts/verify-assistant-v2.sh, never point the test at user PIDs.
// Requires macOS clang; exits automatically after 20 seconds if not stopped.
#include <unistd.h>
int main(void){sleep(20);return 0;}
