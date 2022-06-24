import { HardhatRuntimeEnvironment } from "hardhat/types";

module.exports = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre;
  const { deploy } = deployments;

  const { admin } = await getNamedAccounts();
  // deploy with 10,000,000 mock LP tokens in circulation
  await deploy("MLPToken", {
    from: admin,
    args: [10000000],
    log: true,
    deterministicDeployment: false,
  });
};
module.exports.tags = ["MLPToken"];
