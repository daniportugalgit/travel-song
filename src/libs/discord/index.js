const fs = require("node:fs");
const path = require("path");
const Env = require("../../base/Env");
const { colors, print } = require("../../base/log");
const {
  Client,
  GatewayIntentBits,
  Partials,
  EmbedBuilder,
  ActionRowBuilder,
  ButtonBuilder,
  ButtonStyle,
} = require("discord.js");

const eventsFolder = path.resolve(__dirname, "./events");
const eventsFiles = fs.readdirSync(eventsFolder).filter((file) => file.endsWith(".js"));

const { roles } = require("./roles/roles");
const { channelList } = require("./channels");

const DISCORD_ENV = Env.getString("DISCORD_ENV");

class Discord {
  constructor() {
    this.client = new Client({
      intents: [
        GatewayIntentBits.Guilds,
        GatewayIntentBits.GuildMembers,
        GatewayIntentBits.GuildMessages,
        GatewayIntentBits.MessageContent,
        GatewayIntentBits.DirectMessages,
        GatewayIntentBits.GuildPresences,
        GatewayIntentBits.DirectMessageReactions,
        GatewayIntentBits.GuildMessageReactions,
      ],
      partials: [Partials.Channel, Partials.Message, Partials.Reaction],
    });

    this.knownRoles = roles;
    this.channels = channelList;
  }

  async init() {
    print(colors.yellow, `🤖 Initializing Discord client...`);

    this.setEventListeners();

    await new Promise((resolve) => {
      this.client.once("ready", () => {
        print(colors.green, `🤖 Discord client ready!`);
        resolve(); // Resolve the promise when the ready event fires
      });

      this.client.on("error", (error) => {
        print(colors.red, `🤖 Discord client error: ${error.message}`);
      });

      print(colors.yellow, `🤖 Logging in...`);
      this.client.login(Env.getString("DISCORD_TOKEN"));
    });
  }

  setEventListeners() {
    print(colors.yellow, `🤖 Setting event listeners...`);
    for (const file of eventsFiles) {
      const event = require(`${eventsFolder}/${file}`);
      if (event.once) {
        this.client.once(event.name, (...args) => event.execute(...args));
      } else {
        this.client.on(event.name, (...args) => event.execute(...args));
      }
      print(colors.cyan, `🤖 Event listener set for ${event.name}`);
    }
  }

  async messageUser(userId, message) {
    await this.client.users.send(userId, message);
  }

  async messageChannel(channelId, message) {
    const channel = this.client.channels.cache.get(this.channelID(channelId));

    try {
      await channel.send(message);
    } catch (e) {
      print(colors.red, `🤖 Discord Error sending message to channel ${channelId}: ${e.message}`);
    }
  }

  async messageTest(message) {
    await this.messageChannel(this.channels.test, message);
  }

  async messageMonitor(message) {
    await this.messageChannel(this.channels.monitor, message);
  }

  async messageProsperityWars(message) {
    await this.messageChannel(this.channels.prosperityWars, message);
  }

  async messageRoar(message) {
    await this.messageChannel(this.channels.roar, message);
  }

  async messageRewards(message) {
    await this.messageChannel(this.channels.rewards, message);
  }

  async setStasherLevel(userId, level) {
    // First, we get the member:
    const member = this.idToMember(userId);

    // then we do the same for Stasher Level roles, removing them all if they exist
    const stasherLevelRoles = Object.values(this.knownRoles).filter((role) =>
      role.name.startsWith("Stasher Level")
    );
    const hasStasherLevelRole = stasherLevelRoles.some((role) => this.hasRole(member, role.id));
    // if he has any of the Stasher Level roles, we remove them
    if (hasStasherLevelRole) {
      for (let i = 0; i < stasherLevelRoles.length; i++) {
        const role = stasherLevelRoles[i];
        await this.removeRole(member, role.id);
      }
    }

    // then, we add the new role, which is one of the knownRoles that start with "Stasher Level", followed by the level that we want to add
    const newRole = Object.values(this.knownRoles).find((role) =>
      role.name.startsWith(`Stasher Level ${level}`)
    );

    if (newRole) {
      // but only if the user doesn't have it already, and only if `level` is not undefined
      if (!this.hasRole(member, newRole.id)) {
        await this.addRole(member, newRole.id);
      }
    }
  }

  idToMember(id) {
    return this.client.guilds.cache.first().members.cache.get(id);
  }

  hasRole(member, roleId) {
    return member.roles.cache.has(roleId);
  }

  async addRole(member, roleId) {
    const role = this.client.guilds.cache.first().roles.cache.get(roleId);
    await member.roles.add(role);
  }

  async removeRole(member, roleId) {
    const role = this.client.guilds.cache.first().roles.cache.get(roleId);
    await member.roles.remove(role);
  }

  async addVerifiedRole(member) {
    try {
      await this.removeRole(member, "1187352526031441990");
    } catch (e) {
      console.log(e);
    }

    try {
      await this.addRole(member, "1163532021650432110");
    } catch (e) {
      console.log(e);
    }
  }

  async addUnverifiedRoleToAllUnverifiedMembers() {
    const members = this.client.guilds.cache.first().members.cache;
    const verifiedRole = this.client.guilds.cache.first().roles.cache.get("1163532021650432110");
    const unverifiedRole = this.client.guilds.cache.first().roles.cache.get("1187352526031441990");
    const commMemberRole = this.client.guilds.cache.first().roles.cache.get("894349432215199794");

    const total = members.size;
    console.log(`Found ${total} members in the server.`);

    let count = 0;
    let addedCount = 0;
    let skippedCount = 0;

    for (const [id, member] of members) {
      count++;
      if (
        !this.hasRole(member, verifiedRole.id) &&
        !this.hasRole(member, "1187352526031441990") &&
        this.hasRole(member, commMemberRole.id)
      ) {
        console.log(`Adding Role to (${count}/${total}): ${member.user.tag}...`);
        await this.addRole(member, "1187352526031441990");
        addedCount++;
        console.log(`>>> ✅ Added ${addedCount} | ❌ Skipped ${skippedCount} <<<`);
      } else {
        skippedCount++;
        console.log(`❌ Skipped (${count}/${total}): ${member.user.tag}`);
      }
    }

    console.log(`FINISH! TOTAL >>> ✅ Added ${addedCount} | ❌ Skipped ${skippedCount} <<<`);

    return {
      success: true,
      totalPlayers: total,
      addedCount,
      skippedCount,
    };
  }

  channelID(channelId) {
    if (DISCORD_ENV === "DEV") {
      return this.channels.test;
    } else {
      return channelId;
    }
  }
}

module.exports = new Discord();
