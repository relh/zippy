import zippy/ziparchives

block:
  # The ZIP declares one byte but actually expands to 4096 bytes.
  let archive = openZipArchive("tests/data/ziparchives/understated-size.zip")
  defer: archive.close()
  doAssert archive.extractFile("payload", 4096).len == 4096
  doAssertRaises(ZippyError):
    discard archive.extractFile("payload", 4095)
  doAssertRaises(ZippyError):
    discard archive.extractFile("payload", 0)
