module lieferando;

import arsd.dom;

import vibe.stream.operations;
import vibe.http.client;

import std.conv;
import std.regex;
import std.string;

import data;

Shop downloadShop(string url)
{
	string html;
	requestHTTP(url, (scope req) {
		req.headers.addField("User-Agent",
			"Mozilla/5.0 (Windows NT 6.1; Win64; x64; rv:59.0) Gecko/20100101 Firefox/59.0");
		req.headers.addField("Accept",
			"text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8");
	}, (scope res) { html = res.bodyReader.readAllUTF8; });

	auto document = new Document(html);

	Shop ret;

	auto h1 = document.querySelector(".restaurant-info > h1");
	if (!h1)
		ret.name = url;
	else
		ret.name = h1.innerText.strip;

	foreach (group; document.querySelectorAll(".menu-meals-group"))
	{
		foreach (child; group.children)
		{
			if (child.className == "menu-category-head" || child.className == "menu-meals-group-category")
			{
				Shop.Item item;
				item.header = true;
				if (auto span = child.querySelector("span"))
					item.name = span.innerText.strip;
				else
					item.name = child.innerText.strip;
				if (auto descriptionElement = child.querySelector(`.menu-category-description`))
					item.description = descriptionElement.innerText.replaceAll(ctRegex!`\s+`, " ").strip;
				ret.items ~= item;
			}
			else if (child.className == "category-menu-meals")
			{
				foreach (meal; child.querySelectorAll(".meal"))
				{
					auto priceElement = meal.querySelector(`span[itemprop="price"]`);
					auto nameElement = meal.querySelector(`span[itemprop="name"]`);

					if (!priceElement || !nameElement)
						continue;

					Shop.Item item;
					auto price = parsePrice(priceElement.innerText.strip);
					if (price != price) // isnan
						continue;
					item.variants ~= Shop.Item.Option(price);
					item.name = nameElement.innerText.strip;
					if (auto descriptionElement = meal.querySelector(`.meal-description-texts`))
						item.description = descriptionElement.innerText.replaceAll(ctRegex!`\s+`,
								" ").strip.prettyDescription(item.name);
					ret.items ~= item;
				}
			}
		}
	}

	return ret;
}

string prettyDescription(string description, string name)
{
	if (description.startsWith(name))
		description = description[name.length .. $].stripLeft;
	return description;
}

double parsePrice(string s)
{
	auto match = s.matchFirst(ctRegex!`(\d+)[.,](\d\d)`);
	if (match)
		return match[1].to!int + match[2].to!int * 0.01;
	else
		return double.nan;
}
