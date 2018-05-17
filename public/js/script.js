var step = 0;
var initiatedOrder = false;
var sentOrder = false;

window.onbeforeunload = function (e) {
	if (initiatedOrder && !sentOrder) {
		return "Bestellung wurde noch nicht abgesendet";
	}
};

var profileSelector = document.querySelector("#profile");
var selectedProfile = profileSelector.value;
profileSelector.onchange = function () {
	var guest = document.querySelector("#guest");
	if (profileSelector.value == "guest") {
		guest.classList.remove("hidden");
		guest.querySelector("input").value = "";
	}
	else if (!guest.classList.contains("hidden"))
		guest.classList.add("hidden");
	selectedProfile = profileSelector.value;
}

function getProfileName() {
	if (userData && selectedProfile == userData.username)
		return selectedProfile;
	else if (selectedProfile == "guest")
		return (document.querySelector("#guest input").value || "Gast") + (userData ? (" (via " + userData.username + ")") : "");
	else
		return selectedProfile + (userData ? (" (via " + userData.username + ")") : "");
}

var nextButton = document.querySelector("button.next");

document.querySelector("button.prev").onclick = function () {
	document.querySelector('.step[data-step="' + step + '"]').classList.add("inactive");
	if (step > 0)
		step--;
	document.querySelector('.step[data-step="' + step + '"]').classList.remove("inactive");
	nextButton.textContent = "Weiter";
	refreshStep();
};

var softDisabled;
nextButton.onclick = function () {
	if (softDisabled) return;
	if (!checkBeforeNext()) return;
	initiatedOrder = true;
	document.querySelector('.step[data-step="' + step + '"]').classList.add("inactive");
	if (step < 2)
		step++;
	else
		doOrder();
	if (step == 2)
		nextButton.textContent = "Bestellen";
	else
		nextButton.textContent = "Weiter";
	softDisabled = true;
	setTimeout(function () {
		softDisabled = false;
	}, 400);
	document.querySelector('.step[data-step="' + step + '"]').classList.remove("inactive");
	refreshStep();
};

if (userData) {
	document.querySelector('.step[data-step="0"]').classList.add("inactive");
	document.querySelector('.step[data-step="1"]').classList.remove("inactive");
	step = 1;
	refreshStep();
}

var availableItems = document.querySelectorAll(".selector > ul.items > li");
for (var i = 0; i < availableItems.length; i++) {
	if (!availableItems[i].classList.contains("header"))
		availableItems[i].onclick = changeSelectedItem.bind(availableItems[i]);
}

var priceInput = document.querySelector("#price input");
var noteInput = document.querySelector("#note input");
var selectedName = document.querySelector("#selectedname");

var selectedItem;
function changeSelectedItem() {
	if (selectedItem)
		selectedItem.classList.remove("active");
	this.classList.add("active");
	selectedItem = this;
	selectedItemData = JSON.parse(this.getAttribute("data"));
	var price = parseFloat(this.getAttribute("data-price") || "0");
	selectedName.textContent = this.querySelector(".name").textContent.trim();
	priceInput.disabled = false;
	noteInput.disabled = false;
	priceInput.value = price;
	noteInput.value = "";
	var icon = document.querySelector("img.icon");
	if (selectedItemData.icon != icon.src) {
		icon.style.display = "none";
		icon.src = selectedItemData.icon;
		if (selectedItemData.icon) {
			icon.onload = function () {
				icon.style.display = "block";
			};
		}
	}
}

var cart = [];

document.querySelector(".selector > .customization > button.add").onclick = putSelectedIntoCart;

function putSelectedIntoCart() {
	if (!selectedItem)
		return alert("Bitte ein Gericht auswählen!");
	if (!priceInput.value || /* nan check integrated */ !(parseFloat(priceInput.value) > 0))
		return alert("Bitte einen Preis angeben!");
	selectedItem.classList.remove("active");
	selectedItem = undefined;
	var price = parseFloat(priceInput.value);
	var note = noteInput.value || "";
	priceInput.disabled = true;
	noteInput.disabled = true;
	priceInput.value = 0;
	noteInput.value = "";
	cart.push({
		item: selectedName.textContent,
		price: price,
		note: note
	});
	refreshCart();
}

function refreshCart() {
	var items = document.querySelector(".cart > table.items > tbody");
	while (items.firstChild)
		items.removeChild(items.firstChild);
	var total = 0;
	for (var i = 0; i < cart.length; i++) {
		total += cart[i].price;

		var item = document.createElement("tr");
		var remove = document.createElement("td");
		remove.textContent = "X";
		remove.onclick = function () {
			var i = cart.indexOf(this);
			cart.splice(i, 1);
			refreshCart();
		}.bind(cart[i]);
		var name = document.createElement("td");
		name.textContent = cart[i].item;
		var price = document.createElement("td");
		price.textContent = cart[i].price.toFixed(2) + " €";
		var note = document.createElement("td");
		note.textContent = cart[i].note || "n/a";
		item.appendChild(remove);
		item.appendChild(name);
		item.appendChild(price);
		item.appendChild(note);
		items.appendChild(item);
	}
	document.querySelector(".cart > .total > span").textContent = total.toFixed(2);
}

function checkBeforeNext() {
	if (step == 1) {
		if (cart.length == 0 && selectedItem)
			putSelectedIntoCart();
		if (cart.length == 0) {
			alert("Bitte wählen Sie ein Gericht aus!");
			return false;
		}
	}
	return true;
}

function refreshStep() {
	if (step == 2) {
		document.querySelector("form.final span.price").textContent = "Error";
		var total = 0;
		for (var i = 0; i < cart.length; i++)
			total += cart[i].price;
		document.querySelector("form.final span.price").textContent = total.toFixed(2) + " €";
		document.querySelector("form.final span.profile").textContent = getProfileName();
	}
}

function doOrder() {
	nextButton.disabled = true;
	var xhr = new XMLHttpRequest();
	xhr.open("POST", "/order");
	xhr.setRequestHeader("Content-Type", "application/json; charset=utf-8");
	xhr.send(JSON.stringify({
		user: getProfileName(),
		cart: cart,
		note: document.querySelector("form.final .note").value,
		payonline: (document.getElementById("payonline") || { checked: false }).checked
	}));
	xhr.onerror = function () {
		nextButton.disabled = false;
		alert("Fehler bei der Bestellung!");
	};
	xhr.onload = function () {
		if (xhr.status >= 200 && xhr.status < 300) {
			alert("Bestellung abgesendet");
			sentOrder = true;
			window.location.href = "/view";
		}
		else if (xhr.status == 402) {
			nextButton.disabled = false;
			alert("Guthaben reicht nicht aus!");
		}
		else {
			nextButton.disabled = false;
			alert("Fehler bei der Bestellung!");
		}
	};
}
