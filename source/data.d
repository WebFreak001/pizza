module data;

import vibe.d;

import mongoschema;

import std.datetime;
import std.string;

struct Shop
{
	struct Item
	{
		struct Option
		{
			@optional double price;
			@optional string prefix, suffix;
		}

		@optional string icon;
		string name;
		@optional string description;
		@optional Option[] variants;
		@optional bool header;

		string variantName(Option variant)
		{
			string ret = name;
			if (variant.prefix)
				ret = variant.prefix ~ ' ' ~ ret;
			if (variant.suffix)
				ret = ret ~ ' ' ~ variant.suffix;
			return ret;
		}
	}

	string name;
	Item[] items;

	mixin MongoSchema;
}

struct Order
{
	struct CartEntry
	{
	@optional:
		string item;
		double price;
		string note;
	}

	@optional string id;
	string user;
	CartEntry[] cart;
	@optional string note;
	@optional bool payed;
	@optional bool payonline;

	double totalCost() @property const
	{
		double total = 0;
		foreach (item; cart)
			total += item.price;
		return total;
	}
}

struct OrderHistory
{
	BsonObjectID place;
	Order[] orders;
	SysTime at;

	mixin MongoSchema;
}

struct SessionData
{
@optional:
	BsonObjectID currentShop;
	SysTime date;
	Order[] orders;
	bool orderClosed;
}

SessionData sd;

SessionData readSessionData()
{
	if (existsFile("session.json"))
		return readFileUTF8("session.json").deserializeJson!SessionData;
	else
		return SessionData.init;
}

void writeSessionData(SessionData data)
{
	writeFileUTF8(NativePath("session.json"), serializeToPrettyJson(data));
}

struct User
{
	@mongoUnique string username;
	ubyte[] password, salt;
	string givenname, realname;
	bool admin, unregistered;
	long money;

	mixin MongoSchema;
}

User getUser(scope HTTPServerRequest req)
{
	if (!req.session)
		return User.init;
	string name = req.session.get!string("username");
	if (!name.length)
		return User.init;
	auto user = User.tryFindOne(["username" : name]);
	if (user.isNull)
		return User.init;
	else
		return user.get;
}
