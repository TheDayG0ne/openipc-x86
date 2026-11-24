#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <linux/videodev2.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#define W 1280
#define H 720
#define SIZE (W*H*2)
static int camera = -1, next, active;
static unsigned char *maps[4];
static unsigned frame;

int open(const char *path, int flags, ...) {
    static int (*real_open)(const char *, int, ...);
    if (!real_open) real_open = dlsym(RTLD_NEXT, "open");
    mode_t mode = 0;
    if (flags & O_CREAT) { va_list ap; va_start(ap, flags); mode = va_arg(ap, int); va_end(ap); }
    const char *device = getenv("UVC_DEVICE");
    if (device && !strcmp(path, device) && !strcmp(device, "/tmp/divinus-fake-video")) {
        int fd = memfd_create("fake-v4l2", 0);
        if (fd < 0 || ftruncate(fd, SIZE * 4)) return -1;
        camera = fd;
        fprintf(stderr, "fixture: opened fake V4L2 fd=%d\n", fd);
        return fd;
    }
    return real_open(path, flags, mode);
}
int ioctl(int fd, unsigned long req, ...) {
    static int (*real_ioctl)(int, unsigned long, ...);
    if (!real_ioctl) real_ioctl = dlsym(RTLD_NEXT, "ioctl");
    va_list ap; va_start(ap, req); void *arg = va_arg(ap, void *); va_end(ap);
    if (fd != camera) return real_ioctl(fd, req, arg);
    if (req == VIDIOC_QUERYCAP) {
        struct v4l2_capability *c = arg; memset(c, 0, sizeof(*c));
        strcpy((char *)c->driver, "test-fixture"); c->capabilities = V4L2_CAP_VIDEO_CAPTURE | V4L2_CAP_STREAMING; return 0;
    }
    if (req == VIDIOC_S_FMT) {
        struct v4l2_format *f = arg; f->fmt.pix.width=W; f->fmt.pix.height=H;
        f->fmt.pix.pixelformat=V4L2_PIX_FMT_YUYV; f->fmt.pix.bytesperline=W*2; f->fmt.pix.sizeimage=SIZE; return 0;
    }
    if (req == VIDIOC_G_PARM) { struct v4l2_streamparm *p=arg; p->parm.capture.timeperframe.numerator=1; p->parm.capture.timeperframe.denominator=10; return 0; }
    if (req == VIDIOC_REQBUFS) { ((struct v4l2_requestbuffers *)arg)->count=4; return 0; }
    if (req == VIDIOC_QUERYBUF) { struct v4l2_buffer *b=arg; if (b->index>=4) { errno=EINVAL; return -1; } b->length=SIZE; b->m.offset=b->index*SIZE; return 0; }
    if (req == VIDIOC_QBUF) return 0;
    if (req == VIDIOC_STREAMON) { active=1; fprintf(stderr,"fixture: STREAMON YUYV %dx%d 10fps\n", W,H); return 0; }
    if (req == VIDIOC_STREAMOFF) { active=0; return 0; }
    if (req == VIDIOC_DQBUF && active) {
        struct timespec delay={0,100000000}; nanosleep(&delay, NULL);
        int i=next++%4; if (!maps[i]) { maps[i]=mmap(NULL,SIZE,PROT_READ|PROT_WRITE,MAP_SHARED,camera,i*SIZE); if(maps[i]==MAP_FAILED) return -1; }
        for (int y=0;y<H;y++) for (int x=0;x<W;x+=2) {
            int p=(y*W+x)*2; unsigned char l=(unsigned char)(16+((x/8+y/8+frame*5)%220));
            maps[i][p]=l; maps[i][p+1]=128; maps[i][p+2]=l; maps[i][p+3]=128;
        }
        struct v4l2_buffer *b=arg; b->index=i; b->bytesused=SIZE; struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); b->timestamp.tv_sec=t.tv_sec; b->timestamp.tv_usec=t.tv_nsec/1000; frame++; return 0;
    }
    errno=EINVAL; return -1;
}
