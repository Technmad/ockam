use crate::remote::Ftype;
use ockam_core::Address;

#[derive(Clone, Debug)]
pub(crate) struct Addresses {
    // Used to talk to the service
    pub(crate) main_remote: Address,
    // Used to forward messages inside the node
    pub(crate) main_internal: Address,
    // Used to receive heartbeats
    pub(crate) heartbeat: Address,
    // Used to receive completion callback
    pub(crate) completion_callback: Address,
}

impl Addresses {
    pub(crate) fn generate(ftype: Ftype) -> Self {
        let type_str = ftype.str();
        let main_remote =
            Address::random_tagged(&format!("RemoteForwarder.{}.main_remote", type_str));
        let main_internal =
            Address::random_tagged(&format!("RemoteForwarder.{}.main_internal", type_str));
        let heartbeat = Address::random_tagged(&format!("RemoteForwarder.{}.heartbeat", type_str));
        let completion_callback =
            Address::random_tagged(&format!("RemoteForwarder.{}.child", type_str));

        Self {
            main_remote,
            main_internal,
            heartbeat,
            completion_callback,
        }
    }
}
