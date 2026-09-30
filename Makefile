# Makefile —— theos 工程
TARGET := iphone:clang:latest:14.0
ARCHS := arm64
TWEAK_NAME := WeChatKeywordCleaner
WeChatKeywordCleaner_FILES := Tweak.xm KeywordCleanerUI.m WeChatBridge.m
WeChatKeywordCleaner_CFLAGS := -fobjc-arc
WeChatKeywordCleaner_FRAMEWORKS := UIKit Foundation

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 WeChat"
