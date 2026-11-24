################################################################################
# divinus-webui
################################################################################

DIVINUS_WEBUI_VERSION = local
DIVINUS_WEBUI_SITE = $(BR2_EXTERNAL_X86_PATH)/../divinus-webui
DIVINUS_WEBUI_SITE_METHOD = local
DIVINUS_WEBUI_LICENSE = MIT
DIVINUS_WEBUI_LICENSE_FILES = LICENSE

define DIVINUS_WEBUI_INSTALL_TARGET_CMDS
	$(INSTALL) -d $(TARGET_DIR)/var/www/a
	$(INSTALL) -m 644 $(@D)/www/index.html $(@D)/www/favicon.ico $(TARGET_DIR)/var/www/
	$(INSTALL) -m 644 $(addprefix $(@D)/www/a/,divinus.js divinus.css bootstrap.min.css bootstrap.override.css logo.svg) $(TARGET_DIR)/var/www/a/
endef

$(eval $(generic-package))
