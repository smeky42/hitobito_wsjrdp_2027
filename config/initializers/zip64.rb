require "zip"

# rubyzip 3.x defaults Zip.write_zip64_support to true. That makes every zip
# entry -- including the internal parts of a .xlsx built by caxlsx -- declare
# "version needed to extract = 4.5" (Zip64), even for small files that use no
# Zip64 features at all. Strict consumers such as Google Sheets then refuse the
# file. caxlsx >= 4.4.1 (https://github.com/caxlsx/caxlsx/pull/482) means to
# disable this by default, but that does not take effect with rubyzip 3.5.0.
#
# Turn Zip64 off explicitly so exports are written as the classic 2.0 spec.
Zip.write_zip64_support = false
