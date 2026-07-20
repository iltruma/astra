# taiga static IP and firewall
{ ... }:

{
  networking = {
    hostName = "taiga";

    useDHCP = false;
    interfaces.eth0.ipv4.addresses = [
      {
        address = "192.168.178.43";
        prefixLength = 24;
      }
    ];
    defaultGateway = "192.168.178.1";
    nameservers = [
      "192.168.178.2"  # Technitium nebula
      "1.1.1.1"
    ];

    firewall = {
      enable = true;
      allowedTCPPorts = [
        22
        80
        443
        7125  # Moonraker API
      ];
    };
  };
}
