import vibe.d;

import std.algorithm;
import std.conv;
import std.datetime;
import std.math;
import std.random;
import std.uuid;

import mongoschema;
import data;
import crypt.password;

static import lieferando;

Shop aboutToImport;
__gshared bool registerFirstUser;

shared static this()
{
	sd = readSessionData();

	setTimer(5.minutes, { writeSessionData(sd); }, true);

	auto db = connectMongoDB("mongodb://127.0.0.1").getDatabase("pizzas");
	db["users"].register!User;
	db["shops"].register!Shop;
	db["orders"].register!OrderHistory;

	registerFirstUser = User.countAll == 0;

	auto settings = new HTTPServerSettings;
	settings.port = 61224;
	settings.bindAddresses = ["::1", "127.0.0.1"];

	sd.date = Clock.currTime(UTC());

	if (!existsFile("orders"))
		createDirectory("orders");

	settings.sessionStore = new MemorySessionStore;

	auto router = new URLRouter;
	router.get("*", serveStaticFiles("./public/"));
	router.post("/auth", &doLogin);
	router.get("/login", &getLogin);
	router.any("*", &checkAuth);
	router.get("/", &index);
	router.get("/view", &showOrders);
	router.get("/stats", &showStats);
	router.get("/close", &closeOrder);
	router.get("/finish", &finishOrder);
	router.get("/delete-order", &deleteOrder);
	router.get("/logout", &logout);
	router.get("/admin", &getAdmin);
	router.post("/invite", &createInvite);
	router.post("/import", &importShop);
	router.post("/open", &postOpen);
	router.post("/order", &postOrder);
	router.post("/payed", &postPayed);
	router.post("/set_money", &setValue!"money");
	router.post("/set_givenname", &setValue!"givenname");
	router.post("/set_realname", &setValue!"realname");
	router.post("/set_admin", &setValue!"admin");

	listenHTTP(settings, router);
}

void importShop(scope HTTPServerRequest req, scope HTTPServerResponse res)
{
	string url = req.form.get("url");
	if (req.form.get("confirm", "false") == "true")
	{
		if (!aboutToImport.items.length)
			res.writeJsonBody(false);
		else
		{
			aboutToImport.save();
			auto id = aboutToImport.bsonID;
			aboutToImport = Shop.init;
			res.writeJsonBody(id.toString);
		}
	}
	else if (url.canFind("lieferando."))
	{
		aboutToImport = lieferando.downloadShop(url);
		if (aboutToImport.items.length)
		{
			res.writeJsonBody(aboutToImport);
		}
		else
		{
			res.statusCode = 500;
			res.writeJsonBody("no items found in this shop");
		}
	}
	else
	{
		res.statusCode = 400;
		res.writeJsonBody("no importer for this url");
	}
}

void doLogin(scope HTTPServerRequest req, scope HTTPServerResponse res)
{
	string fail = "fail";
	Session sess = req.session ? req.session : res.startSession();
	string username = req.form.get("username");
	string password = req.form.get("password");
	string invite = req.form.get("invite", "");
	auto user = invite.length == 24 ? User.tryFindById(invite)
		: User.tryFindOne(["username" : username]);
	if (username.length < 2 || username == "guest")
	{
		fail = "username";
		goto LoginFail;
	}
	if (password.length < 5)
	{
		fail = "password";
		goto LoginFail;
	}
	if (user.isNull && !registerFirstUser)
		goto LoginFail;
	if (invite.length == 24)
	{
		if (!user.unregistered)
			goto LoginFail;
		if (!User.tryFindOne(["username" : username]).isNull)
		{
			fail = "dupusername";
			goto LoginFail;
		}
		user.username = user.realname = username;
		user.salt = generateSalt[].dup;
		user.password = hashPassword(password, user.salt);
		user.unregistered = false;
		user.save();
	}
	else if (registerFirstUser)
	{
		user = User.init;
		user.username = user.realname = username;
		user.salt = generateSalt[].dup;
		user.password = hashPassword(password, user.salt);
		user.admin = true;
		user.save();
	}
	else if (user.password != hashPassword(password, user.salt))
		goto LoginFail;
	sess.set("username", username);
	res.redirect("/");
	return;
LoginFail:
	res.redirect("/login?login=" ~ fail);
}

void checkAuth(scope HTTPServerRequest req, scope HTTPServerResponse res)
{
	if (!req.getUser.bsonID.valid)
		res.redirect("/login");
}

void logout(scope HTTPServerRequest req, scope HTTPServerResponse res)
{
	res.terminateSession();
	res.redirect("/");
}

void getLogin(scope HTTPServerRequest req, scope HTTPServerResponse res)
{
	string showError = req.query.get("login", "");
	string invite = req.query.get("invite", "");
	res.render!("login.dt", showError, invite);
}

void index(scope HTTPServerRequest req, scope HTTPServerResponse res)
{
	res.render!("index.dt", req, sd);
}

void showOrders(scope HTTPServerRequest req, scope HTTPServerResponse res)
{
	bool admin = req.queryString == "admin" || req.query.get("admin", "no") != "no";
	res.render!("orders.dt", req, admin, sd);
}

void showStats(scope HTTPServerRequest req, scope HTTPServerResponse res)
{
	auto history = OrderHistory.findAll;
	res.render!("stats.dt", req, history);
}

void postOpen(scope HTTPServerRequest req, scope HTTPServerResponse res)
{
	sd.currentShop = BsonObjectID.fromString(req.form.get("place", ""));
	if (!sd.currentShop.valid || Shop.tryFindById(sd.currentShop).isNull)
	{
		res.writeBody("Invalid ID", 500);
		return;
	}
	sd.date = Clock.currTime(UTC());
	sd.orderClosed = false;
	writeSessionData(sd);
	res.redirect("/view?admin");
}

void postOrder(scope HTTPServerRequest req, scope HTTPServerResponse res)
{
	if (!sd.currentShop.valid)
		return;
	auto order = req.json.deserializeJson!Order;
	order.id = randomUUID.toString;
	order.payed = false;
	auto cost = order.totalCost;
	if (order.payonline)
	{
		auto user = req.getUser;
		auto costInt = cast(long) round(cost * 100);
		if (!user.bsonID.valid || user.money < costInt)
		{
			res.writeBody("", 402);
			return;
		}
		user.money -= costInt;
		try
		{
			user.save();
		}
		catch (Exception)
		{
			res.writeBody("Failed to save payment", 500);
			return;
		}
		order.payed = true;
	}
	sd.orders ~= order;
	res.writeBody("Success!", "text/plain");
}

void closeOrder(scope HTTPServerRequest req, scope HTTPServerResponse res)
{
	sd.orderClosed = true;
	res.redirect("/view?admin");
}

void finishOrder(scope HTTPServerRequest req, scope HTTPServerResponse res)
{
	auto id = sd.currentShop;
	sd.currentShop = BsonObjectID.init;
	sd.orderClosed = true;
	OrderHistory(id, sd.orders, sd.date).save();
	sd.orders.length = 0;
	res.redirect("/");
}

void postPayed(scope HTTPServerRequest req, scope HTTPServerResponse res)
{
	bool payed = req.json["payed"].get!bool;
	string id = req.json["id"].get!string;
	foreach (ref order; sd.orders)
	{
		if (order.id != id)
			continue;
		if (order.payonline)
		{
			res.writeBody("false", "application/json");
			return;
		}
		order.payed = payed;
		res.writeBody(payed ? "true" : "false", "application/json");
		return;
	}
}

void deleteOrder(scope HTTPServerRequest req, scope HTTPServerResponse res)
{
	string id = req.query.get("id", "");
	foreach_reverse (i, ref order; sd.orders)
	{
		if (order.id != id)
			continue;
		if (order.payonline)
		{
			res.redirect("/view");
			return;
		}
		sd.orders = sd.orders.remove(i);
		res.redirect("/view");
		return;
	}
}

void getAdmin(scope HTTPServerRequest req, scope HTTPServerResponse res)
{
	if (!req.getUser.admin)
		return;
	res.render!("admin.dt", req);
}

void setValue(string prop)(scope HTTPServerRequest req, scope HTTPServerResponse res)
{
	if (!req.getUser.admin)
		return;
	auto username = req.json["user"].get!string;
	auto user = User.tryFindOne(["username" : username]);
	__traits(getMember, user, prop) = req.json[prop].get!(typeof(__traits(getMember,
			User.init, prop)));
	user.save();
	res.writeJsonBody(user);
}

void createInvite(scope HTTPServerRequest req, scope HTTPServerResponse res)
{
	if (!req.getUser.admin)
		return;
	User user;
	user.username = "guest" ~ uniform!uint.to!string;
	user.unregistered = true;
	user.save();
	res.writeBody(user.bsonID.toString, 200, "text/plain");
}
