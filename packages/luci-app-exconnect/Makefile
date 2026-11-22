include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-exconnect
PKG_VERSION:=0.1.0
PKG_RELEASE:=2
PKG_BUILD_DEPENDS:=luci-base/host

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-exconnect
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=LuCI interface for ExConnect
  DEPENDS:=+luci-light +luci-i18n-base-ru +exconnect
  PKGARCH:=all
endef

define Build/Compile
endef

define Package/luci-app-exconnect/install
	$(INSTALL_DIR) $(1)/www $(1)/usr/lib/lua/luci/i18n
	$(CP) ./htdocs/* $(1)/www/
	$(CP) ./root/* $(1)/
	po2lmo ./po/ru/exconnect.po $(1)/usr/lib/lua/luci/i18n/exconnect.ru.lmo
endef

define Package/luci-app-exconnect/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	rm -f /tmp/luci-indexcache.*
	/etc/init.d/rpcd reload >/dev/null 2>&1
}
exit 0
endef

$(eval $(call BuildPackage,luci-app-exconnect))
