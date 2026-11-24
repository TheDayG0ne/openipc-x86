include $(sort $(wildcard $(BR2_EXTERNAL_X86_PATH)/package/*/*.mk))

ifeq ($(BR2_PACKAGE_X86_DIVINUS_FFMPEG),y)
$(DIVINUS_DIR)/.stamp_configured: ffmpeg x264 host-pkgconf
DIVINUS_OPTIONS = "$(TARGET_CFLAGS) $(TARGET_LDFLAGS) -DDIVINUS_V4L2 -lm -ldl -lpthread"
define DIVINUS_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D)/src clean
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D)/src CC="$(TARGET_CC)" OPT=$(DIVINUS_OPTIONS) UVC_FFMPEG=1
endef
define DIVINUS_INSTALL_INIT_SYSV
	$(INSTALL) -D -m 755 $(BR2_EXTERNAL_GENERAL_PATH)/package/divinus/files/S95divinus $(TARGET_DIR)/etc/init.d/S95divinus
endef
endif
