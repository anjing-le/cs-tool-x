import CryptoKit
import Darwin
import Foundation
let args=CommandLine.arguments
guard args.count==3 else { fatalError("Usage: generate-update-key.swift private-key-file public-key-file") }
let target=URL(fileURLWithPath:args[1]);let publicURL=URL(fileURLWithPath:args[2])
let key:Curve25519.Signing.PrivateKey
if FileManager.default.fileExists(atPath:target.path) {
    let attributes=try FileManager.default.attributesOfItem(atPath:target.path)
    guard (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,
          (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
          attributes[.type] as? FileAttributeType == .typeRegular,
          let seed=Data(base64Encoded:try String(contentsOf:target,encoding:.utf8).trimmingCharacters(in:.whitespacesAndNewlines)) else { fatalError("Signing file must be a regular, current-user-owned 0600 file") }
    key=try Curve25519.Signing.PrivateKey(rawRepresentation:seed)
} else {
    try FileManager.default.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
    key=Curve25519.Signing.PrivateKey()
    let fd=open(target.path,O_WRONLY|O_CREAT|O_EXCL,0o600)
    guard fd>=0 else { fatalError("Cannot create private signing file") }
    let handle=FileHandle(fileDescriptor:fd,closeOnDealloc:true)
    try handle.write(contentsOf:Data((key.rawRepresentation.base64EncodedString()+"\n").utf8));try handle.close()
}
try (key.publicKey.rawRepresentation.base64EncodedString()+"\n").write(to:publicURL,atomically:true,encoding:.utf8)
print("Update verification public key saved. Private key stays in the external 0600 file.")
