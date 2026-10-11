actor { type T1 = [Bool]; transient var value : ?T1 = null; public func go() : async () { value := value }; }
