################################################################################
# divinus-webui
################################################################################

DIVINUS_WEBUI_VERSION = local
DIVINUS_WEBUI_SITE = $(BR2_EXTERNAL_X86_PATH)/../divinus-webui
DIVINUS_WEBUI_SITE_METHOD = local
DIVINUS_WEBUI_LICENSE = MIT
DIVINUS_WEBUI_LICENSE_FILES = LICENSE

define DIVINUS_WEBUI_INSTALL_TARGET_CMDS
	$(INSTALL) -d $(TARGET_DIR)/var/www
	cp -a $(@D)/www/. $(TARGET_DIR)/var/www/
	find $(TARGET_DIR)/var/www -type f -exec chmod 0644 {} +
	find $(TARGET_DIR)/var/www/cgi-bin -type f -name '*.cgi' -exec chmod 0755 {} +
endef

$(eval $(generic-package))
