################################################################################
# divinus-webui
################################################################################

DIVINUS_WEBUI_VERSION = local
DIVINUS_WEBUI_SITE = $(BR2_EXTERNAL_X86_PATH)/../divinus-webui
DIVINUS_WEBUI_SITE_METHOD = local
DIVINUS_WEBUI_LICENSE = MIT
DIVINUS_WEBUI_LICENSE_FILES = LICENSE

define DIVINUS_WEBUI_INSTALL_TARGET_CMDS
	$(INSTALL) -d $(TARGET_DIR)/var/www $(TARGET_DIR)/usr/share/divinus-webui
	cp -a $(@D)/www/. $(TARGET_DIR)/usr/share/divinus-webui/
	cp -a $(@D)/www/. $(TARGET_DIR)/var/www/
	rm -rf $(TARGET_DIR)/var/www/cgi-bin
	find $(TARGET_DIR)/var/www -type f -exec chmod 0644 {} +
endef

$(eval $(generic-package))
