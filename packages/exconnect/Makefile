include $(TOPDIR)/rules.mk

PKG_NAME:=exconnect
PKG_VERSION:=0.2.0
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/exconnect
  SECTION:=net
  CATEGORY:=Network
  TITLE:=ExConnect VPN and transparent proxy service
  PKGARCH:=all
  DEPENDS:=+xray-core +ucode +ucode-mod-uci +ucode-mod-fs +rpcd +jshn +curl +ca-bundle +firewall4 +kmod-nft-tproxy +ip-full +ss +flock
endef

define Package/exconnect/description
  Manages Xray client profiles, transparent routing and custom DAT rule lists.
endef

define Build/Compile
endef

define Package/exconnect/conffiles
/etc/config/exconnect
endef

define Package/exconnect/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || /etc/init.d/rpcd reload >/dev/null 2>&1
exit 0
endef

define Package/exconnect/install
	$(INSTALL_DIR) $(1)/etc/config $(1)/etc/init.d $(1)/etc/exconnect
	$(INSTALL_CONF) ./files/etc/config/exconnect $(1)/etc/config/exconnect
	$(INSTALL_BIN) ./files/etc/init.d/exconnect $(1)/etc/init.d/exconnect
	$(INSTALL_DIR) $(1)/usr/libexec/exconnect $(1)/usr/libexec/rpcd
	$(INSTALL_DATA) ./files/usr/libexec/exconnect/generate.uc $(1)/usr/libexec/exconnect/generate.uc
	$(INSTALL_DATA) ./files/usr/libexec/exconnect/subscriptions.uc $(1)/usr/libexec/exconnect/subscriptions.uc
	$(INSTALL_BIN) ./files/usr/libexec/exconnect/control $(1)/usr/libexec/exconnect/control
	$(INSTALL_BIN) ./files/usr/libexec/exconnect/run $(1)/usr/libexec/exconnect/exconnect-core
	$(LN) exconnect-core $(1)/usr/libexec/exconnect/run
	$(INSTALL_BIN) ./files/usr/libexec/exconnect/probe $(1)/usr/libexec/exconnect/probe
	$(INSTALL_BIN) ./files/usr/libexec/rpcd/exconnect $(1)/usr/libexec/rpcd/exconnect
	$(INSTALL_BIN) ./files/usr/libexec/rpcd/exconnect-subscriptions $(1)/usr/libexec/rpcd/exconnect-subscriptions
endef

$(eval $(call BuildPackage,exconnect))
