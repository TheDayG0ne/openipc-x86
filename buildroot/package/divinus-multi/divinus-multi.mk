################################################################################
# divinus-multi: optional launcher for independent Divinus UVC instances
################################################################################

DIVINUS_MULTI_VERSION = local
DIVINUS_MULTI_SITE = $(BR2_EXTERNAL_X86_PATH)/package/divinus-multi
DIVINUS_MULTI_SITE_METHOD = local
DIVINUS_MULTI_LICENSE = GPL-2.0+

# The launcher starts one central Divinus HTTP process and camera-only workers;
# Divinus owns the documented web_port: 0 worker mode.
define DIVINUS_MULTI_INSTALL_TARGET_CMDS
	# Replace the single-instance init hook, never run both launchers.
	rm -f $(TARGET_DIR)/etc/init.d/S95divinus
	$(INSTALL) -D -m 755 $(@D)/S95divinus-multi $(TARGET_DIR)/etc/init.d/S95divinus-multi
	$(INSTALL) -D -m 644 $(@D)/divinus-multi.conf $(TARGET_DIR)/etc/divinus-multi.conf
endef

$(eval $(generic-package))
