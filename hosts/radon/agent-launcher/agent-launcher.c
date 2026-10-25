/*
 * agent-launcher <job> [args...]
 *
 * macOS privacy protection (TCC) refuses launchd jobs access to an external
 * volume unless the binary launchd started holds Full Disk Access. TCC holds
 * that binary responsible for every process it starts, so this launcher starts
 * the job as its child, waits for it, and never replaces itself with the job.
 * Full Disk Access is granted once, to this file.
 *
 * It runs only jobs that root registered as /etc/agent-launcher.d/<job>, with a
 * minimal environment, so the grant cannot be used to run arbitrary code.
 */

#include <errno.h>
#include <limits.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#ifndef JOBS_DIR
#define JOBS_DIR "/etc/agent-launcher.d"
#endif
#ifndef REQUIRE_ROOT_OWNED_JOBS_DIR
#define REQUIRE_ROOT_OWNED_JOBS_DIR 1
#endif
#ifndef MISSING_JOB_WAIT_SECONDS
#define MISSING_JOB_WAIT_SECONDS 300
#endif

#define EXIT_USAGE 64
#define EXIT_SOFTWARE 70
#define EXIT_NOT_FOUND 127

static volatile sig_atomic_t child_pid = 0;
static volatile sig_atomic_t pending_signal = 0;

static void forward_signal(int sig) {
	if (child_pid > 0)
		kill((pid_t)child_pid, sig);
	else
		pending_signal = sig;
}

static int valid_job_name(const char *name) {
	if (name[0] == '\0' || name[0] == '.')
		return 0;
	for (const char *c = name; *c; c++) {
		int ok = (*c >= 'a' && *c <= 'z') || (*c >= 'A' && *c <= 'Z') ||
			 (*c >= '0' && *c <= '9') || *c == '-' || *c == '_' || *c == '.';
		if (!ok)
			return 0;
	}
	return 1;
}

static int jobs_dir_trusted(void) {
	struct stat st;
	if (stat(JOBS_DIR, &st) != 0) {
		fprintf(stderr, "agent-launcher: %s: %s\n", JOBS_DIR, strerror(errno));
		return 0;
	}
	if (!S_ISDIR(st.st_mode)) {
		fprintf(stderr, "agent-launcher: %s is not a directory\n", JOBS_DIR);
		return 0;
	}
	if (REQUIRE_ROOT_OWNED_JOBS_DIR && (st.st_uid != 0 || (st.st_mode & (S_IWGRP | S_IWOTH)))) {
		fprintf(stderr, "agent-launcher: %s must be owned by root and writable only by root\n",
			JOBS_DIR);
		return 0;
	}
	return 1;
}

int main(int argc, char **argv) {
	if (argc < 2 || !valid_job_name(argv[1])) {
		fprintf(stderr, "usage: agent-launcher <job> [args...]\n");
		return EXIT_USAGE;
	}

	struct sigaction sa;
	memset(&sa, 0, sizeof sa);
	sa.sa_handler = forward_signal;
	sigemptyset(&sa.sa_mask);
	sigaction(SIGTERM, &sa, NULL);
	sigaction(SIGINT, &sa, NULL);
	sigaction(SIGHUP, &sa, NULL);

	if (!jobs_dir_trusted())
		return EXIT_SOFTWARE;

	char path[PATH_MAX];
	if (snprintf(path, sizeof path, "%s/%s", JOBS_DIR, argv[1]) >= (int)sizeof path)
		return EXIT_USAGE;

	/* At boot launchd can start this before the Nix store volume is mounted. */
	for (int waited = 0; access(path, X_OK) != 0; waited++) {
		if (errno != ENOENT || waited >= MISSING_JOB_WAIT_SECONDS || pending_signal) {
			fprintf(stderr, "agent-launcher: %s: %s\n", path, strerror(errno));
			return EXIT_NOT_FOUND;
		}
		sleep(1);
	}
	if (pending_signal)
		return 128 + pending_signal;

	char *env[] = {"PATH=/usr/bin:/bin:/usr/sbin:/sbin", NULL};
	char **child_argv = argv + 1;
	child_argv[0] = path;

	pid_t pid;
	int rc = posix_spawn(&pid, path, NULL, NULL, child_argv, env);
	if (rc != 0) {
		fprintf(stderr, "agent-launcher: cannot start %s: %s\n", path, strerror(rc));
		return EXIT_NOT_FOUND;
	}
	child_pid = pid;
	if (pending_signal)
		kill(pid, pending_signal);

	int status;
	while (waitpid(pid, &status, 0) < 0) {
		if (errno != EINTR) {
			perror("agent-launcher: waitpid");
			return EXIT_SOFTWARE;
		}
	}
	if (WIFEXITED(status))
		return WEXITSTATUS(status);
	if (WIFSIGNALED(status))
		return 128 + WTERMSIG(status);
	return EXIT_SOFTWARE;
}
