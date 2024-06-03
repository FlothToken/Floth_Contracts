const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

module.exports = buildModule("ProjectProposalModule", (m) => {
  const flothAddress = m.getParameter("flothAddress", "0xd6a024303Ad266a34Aab8ca74F40d4E361ACb797");

  const projectProposal = m.contract("ProjectProposal", [flothAddress]);

  return { projectProposal };
});
