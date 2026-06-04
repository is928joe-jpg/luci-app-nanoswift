include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-nanoswift
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-nanoswift
	SECTION:=luci
	CATEGORY:=LuCI
	SUBMENU:=3. Applications
	TITLE:=LuCI for NanoSwift
	DEPENDS:=+libstdcpp
endef

define Package/luci-app-nanoswift/description
	NanoSwift LuCI application for managing SRS services
endef

define Package/luci-app-nanoswift/postinst
#!/bin/sh
[ -n "$$IPKG_INSTROOT" ] || /usr/bin/srs || true
[ -n "$$IPKG_INSTROOT" ] || /etc/init.d/cfnat enable 2>/dev/null || true
[ -n "$$IPKG_INSTROOT" ] || /etc/init.d/sing-box enable 2>/dev/null || true
printf "%s\n" "opkg install luci-app-nanoswift finished!"
exit 0
endef

define Build/Prepare
	rm -rf $(PKG_BUILD_DIR)
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./files/* $(PKG_BUILD_DIR)/
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/luci-app-nanoswift/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_DIR) $(1)/etc
	$(INSTALL_DIR) $(1)/usr/lib/lua

	$(CP) ./files/etc/* $(1)/etc/
	$(CP) ./files/usr/* $(1)/usr/

	[ -f ./files/cfnat/cfnat-$(ARCH_NAME) ] && $(INSTALL_BIN) ./files/cfnat/cfnat-$(ARCH_NAME) $(1)/usr/bin/cfnat || true
	[ -f ./files/convert/convert-$(ARCH_NAME) ] && $(INSTALL_BIN) ./files/convert/convert-$(ARCH_NAME) $(1)/usr/bin/convert || true
	[ -f ./files/srs/srs-downloader-$(ARCH_NAME) ] && $(INSTALL_BIN) ./files/srs/srs-downloader-$(ARCH_NAME) $(1)/usr/bin/srs || true
endef

$(eval $(call BuildPackage,luci-app-nanoswift))
