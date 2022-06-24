import { expect } from "chai";
import { ethers } from "hardhat";

describe("PresaleService", function () {
  before(async function () {
    // Get all accounts
    this.accounts = await ethers.getSigners();
    // Label their roles
    this.admin = this.accounts[0];
    this.nonAdmin = this.accounts[1];
    // Get the contracts ready
    this.PresaleService = await ethers.getContractFactory("PresaleService");
    this.MOKToken = await ethers.getContractFactory("MOKToken");
    this.MLPToken = await ethers.getContractFactory("MLPToken");
    this.UniswapMock = await ethers.getContractFactory("UniswapMock");
  });
  beforeEach(async function () {
    this.mlp = await this.MLPToken.deploy(1000000);
    await this.mlp.deployed();
    this.uniswap = await this.UniswapMock.deploy(this.mlp.address);
    await this.uniswap.deployed();
    this.ps = await this.PresaleService.deploy(this.uniswap.address, 500);
    await this.ps.deployed();
  });
  it("Should set correct state variables", async function () {
    const psUsageFeeBps = await this.ps.usageFeeBps();
    expect(psUsageFeeBps).to.equal(ethers.utils.parseEther("500"));
    const adminRole = await this.ps.ROLE_ADMIN();
    const isAdmin = await this.ps.hasRole(this.admin.address, adminRole);
    expect(isAdmin).to.equal(true);
  });
  it("Should only let admin change usage fee", async function () {
    // Test non-admin
    await expect(this.ps.connect(this.nonAdmin).changeUsageFee(420)).to.be
      .reverted;
    // Nothing changed. Still 500bps
    let psUsageFeeBps = await this.ps.usageFeeBps();
    expect(psUsageFeeBps).to.equal(ethers.utils.parseEther("500"));

    // Test with owner
    await expect(this.ps.changeUsageFee(420)).to.be.reverted;
    // Changed to 420 bps
    psUsageFeeBps = await this.ps.usageFeeBps();
    expect(psUsageFeeBps).to.equal(ethers.utils.parseEther("420"));
  });
  context("With MOK Tokens", function () {
    beforeEach(async function () {
      this.mok = await this.MOKToken.deploy(1000000);
      await this.mok.deployed();
      // Hand out tokens where every account has 1000 tokens
      await this.mok.transfer(
        this.manager1.address,
        ethers.BigNumber.from("1000000000000000000000")
      );
      await this.mok.transfer(
        this.manager2.address,
        ethers.BigNumber.from("1000000000000000000000")
      );
      // Approve transfers
      await this.mok.approve(
        this.manager1.address,
        ethers.constants.MaxUint256
      );
      await this.mok.approve(
        this.manager2.address,
        ethers.constants.MaxUint256
      );
      await this.mok.approve(this.rottery.address, ethers.constants.MaxUint256);
      await this.mok
        .connect(this.manager1)
        .approve(this.rottery.address, ethers.constants.MaxUint256);
      await this.mok
        .connect(this.manager2)
        .approve(this.rottery.address, ethers.constants.MaxUint256);
    });
    it("Should let anyone buy tickets if they have the funds", async function () {
      // set up
      let jackpot, usageFees;
      // Not enough funds
      await expect(
        this.rottery.connect(this.player1).buyTickets(1)
      ).to.be.reverted;
      // Manager as player can buy
      await this.rottery.connect(this.manager1).buyTickets(1);
      jackpot = await this.rottery.jackpot();
      usageFees = await this.rottery.usageFees();
      expect(jackpot).to.equal(ethers.BigNumber.from("19000000000000000000"));
      expect(usageFees).to.equal(ethers.BigNumber.from("1000000000000000000"));
      // Manager as actual manager can buy
      await this.rottery.promoteToManager(this.manager1.address);
      await this.rottery.connect(this.manager1).buyTickets(1);
      // 2 tickets in pool
      jackpot = await this.rottery.jackpot();
      usageFees = await this.rottery.usageFees();
      expect(jackpot).to.equal(ethers.BigNumber.from("38000000000000000000"));
      expect(usageFees).to.equal(ethers.BigNumber.from("2000000000000000000"));
      // Owner can buy
      await this.rottery.buyTickets(1);
      // 3 tickets in pool
      jackpot = await this.rottery.jackpot();
      usageFees = await this.rottery.usageFees();
      expect(jackpot).to.equal(ethers.BigNumber.from("57000000000000000000"));
      expect(usageFees).to.equal(ethers.BigNumber.from("3000000000000000000"));
      // manager2 is still player, can buy multiple tickets
      await this.rottery.connect(this.manager2).buyTickets(10);
      // 13 tickets in pool
      jackpot = await this.rottery.jackpot();
      usageFees = await this.rottery.usageFees();
      expect(jackpot).to.equal(ethers.BigNumber.from("247000000000000000000"));
      expect(usageFees).to.equal(ethers.BigNumber.from("13000000000000000000"));
    });
    it("Should allow only owner to withdraw usage fee pool", async function () {
      // Add money to jackpot
      await this.rottery.connect(this.manager2).buyTickets(1);
      // Not owner
      await expect(
        this.rottery.connect(this.player1).withdrawUsageFees()
      ).to.be.reverted;
      // Owner withdraws
      const currOwnerBal = await this.mok.balanceOf(this.owner.address);
      await this.rottery.withdrawUsageFees();
      // 1 MOK token withdrawn
      const bigSum = ethers.BigNumber.from("1000000000000000000").add(
        currOwnerBal
      );
      const newOwnerBal = await this.mok.balanceOf(this.owner.address);
      expect(newOwnerBal).to.equal(bigSum);
    });
    it("Should allow only owner or manager to draw ticket within the proper timeframe", async function () {
      // Keep track of original balance
      let oldManagerBalance = await this.mok.balanceOf(this.manager1.address);
      // Add money to jackpot
      await this.rottery.connect(this.manager1).buyTickets(2);
      let newManagerBalance = await this.mok.balanceOf(this.manager1.address);
      let numTickets = await this.rottery.ticketPointer();
      expect(numTickets).to.equal(2);
      // Not owner or manager
      console.log("nonowner/manager called draw ticket. no ticket drawn");
      await expect(
        this.rottery.connect(this.player1).drawTicket()
      ).to.be.revertedWith("ERR: Invalid permission");
      // Manager draws ticket
      await this.rottery.promoteToManager(this.manager1.address);
      console.log("manager called draw ticket. ticket drawn");
      await this.rottery.connect(this.manager1).drawTicket();
      console.log(
        "manager called draw ticket again but too soon. ticket not drawn"
      );
      // Draw ticket too soon
      await expect(
        this.rottery.connect(this.manager1).drawTicket()
      ).to.be.revertedWith("ERR: Too soon");
      // 2 MOK tokens lost to usage fees
      let bigDiff = ethers.BigNumber.from("2000000000000000000")
        .sub(oldManagerBalance)
        .abs();
      newManagerBalance = await this.mok.balanceOf(this.manager1.address);
      expect(newManagerBalance).to.equal(bigDiff);
      // Check tickets removed from jackpot pool
      numTickets = await this.rottery.ticketPointer();
      expect(numTickets).to.equal(0);
      // wait 5 minutes
      await new Promise((resolve) => setTimeout(resolve, 300000));
      oldManagerBalance = await this.mok.balanceOf(this.manager2.address);
      // buy ticket
      await this.rottery.connect(this.manager2).buyTickets(3);
      // Owner draws ticket
      console.log("owner called draw ticket. ticket drawn");
      await this.rottery.drawTicket();
      newManagerBalance = await this.mok.balanceOf(this.manager2.address);
      // 3 MOK Tokens lost to usage fees
      bigDiff = ethers.BigNumber.from("3000000000000000000")
        .sub(oldManagerBalance)
        .abs();
      expect(newManagerBalance).to.equal(bigDiff);
    }).timeout(360000);
  });
});
