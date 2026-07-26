BUILD_DIR := $(CURDIR)/build
XCODEBUILD := xcodebuild -derivedDataPath $(BUILD_DIR) -configuration Release CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

.PHONY: all macspaces package clean

all: macspaces

macspaces:
	xcodegen generate --spec project.yml --project . --project-root .
	$(XCODEBUILD) -project MacSpaces.xcodeproj -scheme MacSpaces build

package:
	./Scripts/package-release.sh

clean:
	rm -rf $(BUILD_DIR) MacSpaces.xcodeproj
