import
  std/[os, strutils],
  zippy, zippy/[crc, inflate, ziparchives]

proc add16(bytes: var string, value: int) =
  ## Writes a ZIP fixture field in little endian order.
  for shift in [0, 8]:
    bytes.add char((value shr shift) and 255)

proc add32(bytes: var string, value: uint32) =
  ## Writes a ZIP fixture field in little endian order.
  for shift in [0, 8, 16, 24]:
    bytes.add char((value shr shift) and 255)

proc archiveBytes(data, compressed: string, methodId, declaredSize: int): string =
  ## Creates one ZIP entry with independently controlled size metadata.
  const Name = "payload"
  let checksum = crc32(data)
  result.add32(0x04034b50'u32)
  for value in [20, 0, methodId, 0, 0]:
    result.add16(value)
  result.add32(checksum)
  result.add32(uint32(compressed.len))
  result.add32(uint32(declaredSize))
  result.add16(Name.len)
  result.add16(0)
  result.add Name
  result.add compressed
  let directoryOffset = result.len
  result.add32(0x02014b50'u32)
  for value in [20, 20, 0, methodId, 0, 0]:
    result.add16(value)
  result.add32(checksum)
  result.add32(uint32(compressed.len))
  result.add32(uint32(declaredSize))
  for value in [Name.len, 0, 0, 0, 0]:
    result.add16(value)
  result.add32(0)
  result.add32(0)
  result.add Name
  let directorySize = result.len - directoryOffset
  result.add32(0x06054b50'u32)
  for value in [0, 0, 1, 1]:
    result.add16(value)
  result.add32(uint32(directorySize))
  result.add32(uint32(directoryOffset))
  result.add16(0)

proc checkInflate(compressed, expected: string, limit: int, rejected: bool) =
  ## Checks the output ceiling independently of ZIP metadata.
  var
    output: string
    failed = false
  try:
    inflate(
      output,
      cast[ptr UncheckedArray[uint8]](compressed.cstring),
      compressed.len,
      0,
      limit
    )
    doAssert output == expected
  except ZippyError as error:
    failed = true
    doAssert error.msg in ["Uncompressed data exceeds output limit",
      "Invalid output limit"]
  doAssert failed == rejected
  if limit >= 0 and limit < int.high - 16:
    doAssert output.len <= limit + 13

proc checkArchive(bytes, expected: string, limit: int, rejected: bool) =
  ## Checks extraction with truthful and understated ZIP size fields.
  let path = getTempDir() / ("zippy-output-limit-" & $getCurrentProcessId() & ".zip")
  writeFile(path, bytes)
  defer:
    removeFile(path)
  let reader = openZipArchive(path)
  defer:
    reader.close()
  var failed = false
  try:
    doAssert reader.extractFile("payload", limit) == expected
  except ZippyError as error:
    failed = true
    doAssert error.msg in ["Uncompressed data exceeds output limit",
      "Invalid output limit"]
  doAssert failed == rejected
  doAssert reader.extractFile("payload") == expected

echo "Testing bounded stored, fixed and dynamic DEFLATE output"
block:
  let
    expected = repeat("abcdefghij", 10000)
    stored = compress(expected, NoCompression, dfDeflate)
    dynamic = compress(expected, DefaultCompression, dfDeflate)
    fixedZlib = readFile("tests/data/fixed.z")
    fixed = fixedZlib[2 ..< fixedZlib.len - 4]
    fixedExpected = readFile("tests/data/urls.10K")
  doAssert ((stored[0].ord shr 1) and 3) == 0
  doAssert ((dynamic[0].ord shr 1) and 3) == 2
  doAssert ((fixed[0].ord shr 1) and 3) == 1
  for pair in [(stored, expected), (dynamic, expected), (fixed, fixedExpected)]:
    checkInflate(pair[0], pair[1], pair[1].len, false)
    checkInflate(pair[0], pair[1], pair[1].len - 1, true)
    checkInflate(pair[0], pair[1], 32, true)
    checkInflate(pair[0], pair[1], 0, true)
    checkInflate(pair[0], pair[1], -1, true)
    checkInflate(pair[0], pair[1], int.high, true)

  for methodId in [0, 8]:
    let compressed = if methodId == 0: expected else: dynamic
    for declaredSize in [expected.len, 1]:
      let bytes = archiveBytes(expected, compressed, methodId, declaredSize)
      checkArchive(bytes, expected, expected.len, false)
      checkArchive(bytes, expected, expected.len - 1, true)
      checkArchive(bytes, expected, 32, true)
      checkArchive(bytes, expected, -1, true)
      checkArchive(bytes, expected, int.high, true)

echo "Testing zero-byte output limits"
for methodId in [0, 8]:
  let compressed = if methodId == 0: "" else: compress("", dataFormat = dfDeflate)
  checkArchive(archiveBytes("", compressed, methodId, 0), "", 0, false)
checkInflate(compress("", dataFormat = dfDeflate), "", 0, false)
echo "Output limits passed"
