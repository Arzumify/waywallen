use std::path::PathBuf;

pub mod orchestrator;
pub mod peer;
pub mod proto;
pub mod report;
pub mod spawn;
pub mod tests;
pub mod vk;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Role {
    Orchestrator,
    Peer,
    Renderer,
    Display,
}

#[derive(Debug, Clone)]
pub struct TestArgs {
    pub role: Role,
    pub vk_uuid: Option<[u8; 16]>,
    pub socket: Option<PathBuf>,
    pub slot: u32,
    pub device_idx: Option<usize>,
    pub skip_fanout: bool,
}

impl TestArgs {
    fn parse(argv: &[String]) -> anyhow::Result<Self> {
        let mut role = Role::Orchestrator;
        let mut vk_uuid: Option<[u8; 16]> = None;
        let mut socket: Option<PathBuf> = None;
        let mut slot: u32 = 0;
        let mut device_idx: Option<usize> = None;
        let mut skip_fanout = false;
        let mut it = argv.iter().skip(1).peekable();
        while let Some(a) = it.next() {
            match a.as_str() {
                "--test" => {}
                "--role" => {
                    let v = it
                        .next()
                        .ok_or_else(|| anyhow::anyhow!("--role requires a value"))?;
                    role = match v.as_str() {
                        "orchestrator" => Role::Orchestrator,
                        "peer" => Role::Peer,
                        "renderer" => Role::Renderer,
                        "display" => Role::Display,
                        other => anyhow::bail!("unknown role: {other}"),
                    };
                }
                "--vk-uuid" => {
                    let v = it
                        .next()
                        .ok_or_else(|| anyhow::anyhow!("--vk-uuid requires a value"))?;
                    vk_uuid = Some(parse_uuid_hex(v)?);
                }
                "--socket" => {
                    let v = it
                        .next()
                        .ok_or_else(|| anyhow::anyhow!("--socket requires a path"))?;
                    socket = Some(PathBuf::from(v));
                }
                "--slot" => {
                    let v = it
                        .next()
                        .ok_or_else(|| anyhow::anyhow!("--slot requires a value"))?;
                    slot = v.parse()?;
                }
                "--device" => {
                    let v = it
                        .next()
                        .ok_or_else(|| anyhow::anyhow!("--device requires a value"))?;
                    device_idx = Some(v.parse()?);
                }
                "--skip-fanout" => skip_fanout = true,
                other => anyhow::bail!("unknown self-test arg: {other}"),
            }
        }
        Ok(TestArgs {
            role,
            vk_uuid,
            socket,
            slot,
            device_idx,
            skip_fanout,
        })
    }
}

pub fn run(argv: Vec<String>) -> anyhow::Result<()> {
    let args = TestArgs::parse(&argv)?;
    match args.role {
        Role::Orchestrator => orchestrator::run(args),
        Role::Peer => peer::run_peer(args),
        Role::Renderer => peer::run_renderer(args),
        Role::Display => peer::run_display(args),
    }
}

fn parse_uuid_hex(s: &str) -> anyhow::Result<[u8; 16]> {
    let cleaned: String = s.chars().filter(|c| !c.is_whitespace() && *c != '-').collect();
    if cleaned.len() != 32 {
        anyhow::bail!("expected 32 hex chars, got {}", cleaned.len());
    }
    let mut out = [0u8; 16];
    for i in 0..16 {
        out[i] = u8::from_str_radix(&cleaned[i * 2..i * 2 + 2], 16)?;
    }
    Ok(out)
}

pub fn format_uuid_hex(b: &[u8; 16]) -> String {
    let mut s = String::with_capacity(32);
    for byte in b {
        s.push_str(&format!("{byte:02x}"));
    }
    s
}

#[cfg(test)]
mod unit_tests {
    use super::*;

    #[test]
    fn uuid_roundtrip_strips_dashes() {
        let canonical = "f47ac10b-58cc-4372-a567-0e02b2c3d479";
        let bytes = parse_uuid_hex(canonical).unwrap();
        assert_eq!(format_uuid_hex(&bytes), "f47ac10b58cc4372a5670e02b2c3d479");
    }

    #[test]
    fn parse_args_role_orchestrator_default() {
        let argv = vec!["waywallen".into(), "--test".into()];
        let a = TestArgs::parse(&argv).unwrap();
        assert_eq!(a.role, Role::Orchestrator);
    }

    #[test]
    fn parse_args_role_peer_with_uuid() {
        let argv = vec![
            "waywallen".into(),
            "--test".into(),
            "--role".into(),
            "peer".into(),
            "--vk-uuid".into(),
            "f47ac10b58cc4372a5670e02b2c3d479".into(),
            "--socket".into(),
            "/tmp/x".into(),
        ];
        let a = TestArgs::parse(&argv).unwrap();
        assert_eq!(a.role, Role::Peer);
        assert!(a.vk_uuid.is_some());
        assert_eq!(a.socket.as_deref(), Some(std::path::Path::new("/tmp/x")));
    }
}
