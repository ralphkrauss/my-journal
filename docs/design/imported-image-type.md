# Preserve the actual image type on import

## Problem and design

Mac file drops currently label every non-PNG file image/jpeg. The file picker infers type from the extension and defaults to JPEG. Native decoders may still render these images, but exported data URIs and other clients receive incorrect format metadata.

Derive new attachment mediaType centrally in AppModel.addImage from ImageIO's source type and UniformTypeIdentifiers' MIME mapping, requiring an image source with at least one frame. Keep original bytes unchanged: no lossy conversion, animation flattening, or metadata stripping. Stop before storing when the bytes do not identify a supported native image type. Use the existing error presentation with concise copy: “This file couldn’t be read as an image.” No new control, dialog, layout, or happy-path copy.

Remove the caller-supplied mediaType parameter from AppModel.addImage so both file picker and native paste/drop paths use the same authority. Remove the redundant type hint from the internal native editor callback and call sites as well, so only bytes flow to the single classifier. Existing attachments, archive imports, and sync are unchanged; do not rewrite stored documents. Original-byte exports remain lossless. This does not claim every native image can render in every HTML browser.

A small ImageIO helper identifies type from bytes. Verify with actual generated PNG and TIFF/JPEG encoded data, mismatched caller/file assumptions, and unrecognized bytes. Test the AppModel path if practical to establish emitted DocumentBlock and exact stored attachment bytes; do not test framework MIME tables exhaustively. Keep lock/entry ownership guards intact. Follow with strict checks and native image regressions. No appearance or accessibility changes; existing actionable error presentation remains.
