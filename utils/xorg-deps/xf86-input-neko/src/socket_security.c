#include "socket_security.h"

#include <errno.h>
#include <sys/stat.h>
#include <unistd.h>

int
neko_secure_bound_socket(int *socket_fd, const char *socket_name)
{
    if (socket_fd == NULL || *socket_fd < 0 || socket_name == NULL)
    {
        errno = EINVAL;
        return -1;
    }

    if (chmod(socket_name, S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP) == 0)
    {
        return 0;
    }

    int saved_errno = errno;
    close(*socket_fd);
    *socket_fd = -1;
    unlink(socket_name);
    errno = saved_errno;
    return -1;
}
