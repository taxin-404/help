```shell
git clone ssh://aur@aur.archlinux.org/package.git
cd ~/Projects/package

# For versioned packages (browsercode-bin, uad-ng):
# Edit PKGBUILD → bump pkgver
# Update checksums: makepkg -g or get it from the mainstream
makepkg --printsrcinfo > .SRCINFO
git add PKGBUILD .SRCINFO
git commit -m "Update to vX.Y.Z"
git push origin master

# For -git packages (clickr-git):
# Just bump pkgrel or the pkgver() auto-handles it on build
makepkg --printsrcinfo > .SRCINFO
git add .SRCINFO
git commit -m "Update pkgrel"
git push origin master
```
