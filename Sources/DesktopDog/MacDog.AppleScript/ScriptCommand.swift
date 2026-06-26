// Port of: MacGoose.AppleScript/ScriptCommand.cs

import Foundation

@objc(ScriptCommand)
class ScriptCommand: NSScriptCommand {
    private var EvaluatedArguments: [String: Any] {
        (self.evaluatedArguments as? [String: Any]) ?? [:]
    }

    func PerformCommand() -> Any? {
        fatalError("abstract")
    }

    override func performDefaultImplementation() -> Any? {
        return PerformCommand()
    }

    func GetFloatArg(_ name: String) -> Float? {
        return (EvaluatedArguments[name] as? NSNumber)?.floatValue
    }

    func GetStringArg(_ name: String = "") -> String? {
        let val = EvaluatedArguments[name]
        return (val as? String) ?? (val as? NSString) as String?
    }
}
