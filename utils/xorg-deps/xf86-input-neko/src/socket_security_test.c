#define _POSIX_C_SOURCE 200809L

#include "socket_security.h"

/* Compile the same implementation directly so Automake does not create the
 * shared source once as a libtool object and once as a plain test object. */
#include "socket_security.c"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

static void
fail(const char *message)
{
    perror(message);
    exit(EXIT_FAILURE);
}

int
main(void)
{
    char directory[] = "/tmp/xf86-input-neko-test.XXXXXX";
    if (mkdtemp(directory) == NULL)
    {
        fail("mkdtemp");
    }

    char socket_name[sizeof(((struct sockaddr_un *) 0)->sun_path)];
    int length = snprintf(socket_name, sizeof(socket_name), "%s/input.sock", directory);
    if (length < 0 || (size_t) length >= sizeof(socket_name))
    {
        errno = ENAMETOOLONG;
        fail("socket path");
    }

    int server = socket(AF_UNIX, SOCK_STREAM, 0);
    if (server == -1)
    {
        fail("socket");
    }

    struct sockaddr_un address;
    memset(&address, 0, sizeof(address));
    address.sun_family = AF_UNIX;
    memcpy(address.sun_path, socket_name, (size_t) length + 1);

    mode_t old_umask = umask(0022);
    int bind_status = bind(server, (const struct sockaddr *) &address, sizeof(address));
    umask(old_umask);
    if (bind_status == -1)
    {
        fail("bind");
    }

    if (neko_secure_bound_socket(&server, socket_name) == -1)
    {
        fail("neko_secure_bound_socket");
    }

    struct stat socket_stat;
    if (stat(socket_name, &socket_stat) == -1)
    {
        fail("stat");
    }
    if ((socket_stat.st_mode & 0777) != 0660)
    {
        fprintf(stderr, "socket mode %03o, expected 660\n",
                socket_stat.st_mode & 0777);
        return EXIT_FAILURE;
    }

    if (listen(server, 1) == -1)
    {
        fail("listen");
    }
    int client = socket(AF_UNIX, SOCK_STREAM, 0);
    if (client == -1)
    {
        fail("client socket");
    }
    if (connect(client, (const struct sockaddr *) &address, sizeof(address)) == -1)
    {
        fail("connect");
    }
    close(client);
    close(server);
    unlink(socket_name);

    if (symlink("/definitely/missing/neko-socket", socket_name) == -1)
    {
        fail("symlink");
    }
    server = socket(AF_UNIX, SOCK_STREAM, 0);
    if (server == -1)
    {
        fail("failure-path socket");
    }
    int original_server = server;
    errno = 0;
    if (neko_secure_bound_socket(&server, socket_name) != -1 || errno != ENOENT)
    {
        fprintf(stderr, "expected chmod failure with ENOENT\n");
        return EXIT_FAILURE;
    }
    if (server != -1)
    {
        fprintf(stderr, "failed helper did not invalidate the socket fd\n");
        return EXIT_FAILURE;
    }
    errno = 0;
    if (fcntl(original_server, F_GETFD) != -1 || errno != EBADF)
    {
        fprintf(stderr, "failed helper did not close the socket fd\n");
        return EXIT_FAILURE;
    }
    errno = 0;
    if (lstat(socket_name, &socket_stat) != -1 || errno != ENOENT)
    {
        fprintf(stderr, "failed helper did not unlink the socket path\n");
        return EXIT_FAILURE;
    }

    if (rmdir(directory) == -1)
    {
        fail("rmdir");
    }
    return EXIT_SUCCESS;
}
