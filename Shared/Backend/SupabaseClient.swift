import Foundation
import Supabase

/// App-wide Supabase entry point. Reads URL + anon key from Info.plist, which the build
/// settings populate from `Wilgo/Config/Supabase.local.xcconfig` (gitignored).
enum Backend {
    static let client: SupabaseClient = {
        guard
            let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            !urlString.isEmpty,
            let url = URL(string: urlString),
            let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
            !key.isEmpty
        else {
            fatalError(
                "Supabase config missing — check Wilgo/Config/Supabase.local.xcconfig "
                    + "and that it's linked under Project → Info → Configurations.")
        }
        return SupabaseClient(supabaseURL: url, supabaseKey: key)
    }()
}
