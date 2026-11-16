const heroDashboard = document.querySelector("#hero-dashboard");
const app = document.querySelector(".beaza-app");
const appScroll = document.querySelector(".app-scroll");
const modalBackdrop = document.querySelector("[data-modal-backdrop]");
const modalContent = document.querySelector("[data-modal-content]");
let voiceRecognition = null;
let voiceLanguage = "en-GB";
let receiptObjectUrl = null;
let receiptHasImage = false;

const state = {
  expenses: [],
  dailyLimit: 0,
  goalName: "",
  goalTarget: 0,
  goalCurrent: 0,
  holds: [],
  subscriptions: [],
  coupons: 0,
  private: false,
  historySorted: false,
  importNotice: true,
  showNickname: false,
};

const exampleHistory = [
  { date: "Tue, Nov 3, 2026", name: "Transfer from account ending 3456", amount: 10, time: "18:13", bank: "Al Salam Bank · ••0777", kind: "↙", incoming: true },
  { date: "Tue, Nov 3, 2026", name: "Transfer from account ending 3456", amount: 25, time: "18:12", bank: "Al Salam Bank · ••0777", kind: "↙", incoming: true },
  { date: "Tue, Nov 3, 2026", name: "Debit from your account", amount: 1.5, time: "14:22", bank: "Al Salam Bank · ••0777", kind: "ⓘ" },
  { date: "Tue, Nov 3, 2026", name: "Debit from your account", amount: 4.75, time: "13:29", bank: "Al Salam Bank · ••0777", kind: "ⓘ" },
  { date: "Tue, Nov 3, 2026", name: "Debit from your account", amount: 2.3, time: "11:16", bank: "Al Salam Bank · ••0777", kind: "ⓘ" },
  { date: "Tue, Nov 3, 2026", name: "Debit from your account", amount: 0.4, time: "10:33", bank: "Al Salam Bank · ••0777", kind: "ⓘ" },
  { date: "Tue, Nov 3, 2026", name: "Debit from your account", amount: 7.5, time: "09:40", bank: "Al Salam Bank · ••0777", kind: "ⓘ" },
  { date: "Tue, Nov 3, 2026", name: "Debit from your account", amount: 1.1, time: "09:15", bank: "Al Salam Bank · ••0777", kind: "ⓘ" },
];

const sampleLeaders = [
  ["1", "Saving Falcon #812", "27", "420"],
  ["2", "Saving Falcon #309", "19", "370"],
  ["3", "Saving Falcon #547", "14", "340"],
  ["4", "Budget Captain #126", "21", "290"],
  ["5", "Budget Captain #688", "9", "290"],
  ["6", "Budget Captain #451", "12", "240"],
  ["7", "Budget Captain #935", "6", "220"],
  ["8", "Budget Captain #204", "8", "200"],
  ["9", "Fils Master #773", "4", "180"],
  ["10", "Fils Master #362", "7", "160"],
];

function formatAmount(amount) {
  return Number(amount).toFixed(3);
}

function todayTotal() {
  return state.expenses.reduce((total, expense) => total + expense.amount, 0);
}

function makeElement(tag, className, text) {
  const element = document.createElement(tag);
  if (className) element.className = className;
  if (text !== undefined) element.textContent = text;
  return element;
}

function addIcon(parent, name, className = "app-icon") {
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.classList.add(...className.split(" "));
  const use = document.createElementNS("http://www.w3.org/2000/svg", "use");
  use.setAttribute("href", `#icon-${name}`);
  svg.append(use);
  parent.append(svg);
}

function categoryIcon(category) {
  const icons = {
    Food: "food",
    Transport: "car",
    Bills: "bill",
    Shopping: "bag",
    Other: "receipt",
  };
  return icons[category] || "receipt";
}

function setScreen(screenName) {
  document.querySelectorAll("[data-app-screen]").forEach((screen) => {
    screen.hidden = screen.dataset.appScreen !== screenName;
  });
  document.querySelectorAll(".app-bottom-nav [data-screen]").forEach((button) => {
    button.classList.toggle("active", button.dataset.screen === screenName);
  });
  app.dataset.currentScreen = screenName;
  const isFullScreen = screenName === "ask" || screenName === "account";
  document.querySelector(".app-bottom-nav").hidden = isFullScreen;
  document.querySelector("[data-app-floats]").hidden = screenName !== "today";
  appScroll.scrollTop = 0;
  if (screenName === "history") renderHistory();
}

function renderToday() {
  const total = todayTotal();
  const percent = state.dailyLimit ? Math.round((total / state.dailyLimit) * 100) : 0;

  const limitTitle = document.querySelector("[data-limit-title]");
  limitTitle.textContent = state.dailyLimit ? "Your daily spending limit" : "Set a daily spending limit";
  const dailyCardSub = document.querySelector(".daily-card-sub");
  dailyCardSub.innerHTML = "";
  dailyCardSub.append("Spent today: BHD ");
  const totalValue = makeElement("span", "", formatAmount(total));
  totalValue.dataset.money = "";
  totalValue.dataset.todayTotal = "";
  dailyCardSub.append(totalValue);
  if (state.dailyLimit) {
    const limitText = makeElement("span", "limit-subtext", `  ·  Limit: BHD ${formatAmount(state.dailyLimit)}`);
    dailyCardSub.append(limitText);
  }
  const budgetMeter = document.querySelector("[data-app-budget-meter]");
  const budgetFill = document.querySelector("[data-app-budget-fill]");
  const budgetStatus = document.querySelector("[data-app-budget-status]");
  budgetMeter.hidden = !state.dailyLimit;
  if (state.dailyLimit) {
    const boundedPercent = Math.min(percent, 100);
    budgetFill.style.width = `${boundedPercent}%`;
    budgetFill.dataset.level = percent >= 100 ? "over" : percent >= 80 ? "warning" : "safe";
    budgetMeter.setAttribute("aria-valuenow", String(boundedPercent));
    budgetStatus.textContent = percent >= 100
      ? "Daily limit reached"
      : percent >= 80
        ? `${percent}% used · Getting close`
        : `${percent}% used · BHD ${formatAmount(Math.max(state.dailyLimit - total, 0))} left`;
  } else {
    budgetStatus.textContent = "";
  }

  const todayList = document.querySelector("[data-today-list]");
  todayList.replaceChildren();
  if (state.expenses.length === 0) {
    todayList.append(makeElement("p", "empty-note", "No spending recorded yet. Add an expense to see it here."));
  } else {
    [...state.expenses].reverse().forEach((expense) => {
      todayList.append(makeExpenseRow(expense));
    });
  }

  document.querySelector("[data-expense-summary]").textContent =
    state.expenses.length ? `${state.expenses.length} expense${state.expenses.length === 1 ? "" : "s"} today` : "No small expenses today";
  document.querySelector("[data-week-summary]").textContent = `Last 7 days: BHD ${formatAmount(total)}`;
  document.querySelector("[data-ask-summary]").textContent = total
    ? `BHD ${formatAmount(total)} spent today`
    : "Nothing spent in the last 7 days";

  const insightTitle = document.querySelector("[data-insight-title]");
  const insightCopy = document.querySelector("[data-insight-copy]");
  if (total) {
    insightTitle.textContent = `${state.expenses.length} small step${state.expenses.length === 1 ? "" : "s"} today`;
    insightCopy.textContent = `${percent}% of your daily limit used. Keep checking in as you go.`;
  } else {
    insightTitle.textContent = "A fresh start";
    insightCopy.textContent = "Add a few expenses to see a simple picture of where your money goes.";
  }
  document.querySelector("[data-insight-budget]").textContent = state.dailyLimit
    ? `BHD ${formatAmount(state.dailyLimit)} a day`
    : "No limit set";

  document.querySelectorAll("[data-money]").forEach((element) => {
    element.classList.toggle("is-private", state.private);
  });
}

function makeExpenseRow(expense) {
  const row = makeElement("div", "app-expense-row");
  const icon = makeElement("span", "expense-dot");
  addIcon(icon, categoryIcon(expense.category));
  row.append(icon);
  const description = makeElement("span", "expense-description");
  description.append(expense.description || expense.category);
  description.append(makeElement("small", "", `${expense.time} · Added manually`));
  const value = makeElement("span", "expense-value", `BHD ${formatAmount(expense.amount)}`);
  value.dataset.money = "";
  row.append(description, value);
  return row;
}

function renderHistory() {
  const list = document.querySelector("[data-history-list]");
  list.replaceChildren();
  const currentEntries = state.expenses.map((expense) => ({
    date: "Mon, Nov 16, 2026",
    name: expense.description || expense.category,
    amount: expense.amount,
    time: expense.time,
    bank: "Added manually",
    kind: "ⓘ",
  }));
  const entries = currentEntries.concat(exampleHistory);
  if (state.historySorted) entries.sort((a, b) => b.amount - a.amount);

  const groups = new Map();
  entries.forEach((entry) => {
    if (!groups.has(entry.date)) groups.set(entry.date, []);
    groups.get(entry.date).push(entry);
  });
  groups.forEach((dayEntries, date) => {
    const day = makeElement("section", "history-day");
    const dayTotal = dayEntries.reduce((total, entry) => total + (entry.incoming ? 0 : entry.amount), 0);
    const heading = makeElement("div", "history-day-heading");
    heading.append(makeElement("span", "", date));
    heading.append(makeElement("span", "", `Spent BHD ${formatAmount(dayTotal)}`));
    day.append(heading);
    dayEntries.forEach((entry) => {
      const row = makeElement("div", "app-expense-row");
      const icon = makeElement("span", "expense-dot");
      addIcon(icon, entry.incoming ? "arrow" : "receipt", entry.incoming ? "app-icon incoming-icon" : "app-icon");
      row.append(icon);
      const detail = makeElement("span", "expense-description");
      detail.append(entry.name);
      detail.append(makeElement("small", "", `${entry.time} · ${entry.bank}`));
      const amount = entry.incoming ? `+BHD ${formatAmount(entry.amount)}` : `BHD ${formatAmount(entry.amount)}`;
      const value = makeElement("span", "expense-value", amount);
      value.dataset.money = "";
      row.append(detail, value);
      day.append(row);
    });
    list.append(day);
  });
  document.querySelector("[data-sort-label]").textContent = state.historySorted
    ? `Amount (high to low) (${entries.length})`
    : `Not sorted (${entries.length})`;
  list.querySelectorAll("[data-money]").forEach((element) => element.classList.toggle("is-private", state.private));
}

function renderSaving() {
  document.querySelector("[data-goal-name]").textContent = state.goalName || "No goal yet";
  document.querySelector("[data-goal-current]").textContent = formatAmount(state.goalCurrent);
  document.querySelector("[data-goal-target]").textContent = formatAmount(state.goalTarget);
  const progress = state.goalTarget ? Math.min((state.goalCurrent / state.goalTarget) * 100, 100) : 0;
  document.querySelector("[data-goal-meter]").style.width = `${progress}%`;

  const holdList = document.querySelector("[data-hold-list]");
  holdList.replaceChildren();
  state.holds.forEach((hold) => {
    const item = makeElement("p", "", `${hold.name} · BHD ${formatAmount(hold.amount)} · ready tomorrow`);
    holdList.append(item);
  });

  const subscriptionList = document.querySelector("[data-subscription-list]");
  subscriptionList.replaceChildren();
  state.subscriptions.forEach((subscription) => {
    subscriptionList.append(makeElement("p", "", `${subscription.name} · BHD ${formatAmount(subscription.amount)} / month`));
  });
  if (state.subscriptions.length) {
    document.querySelector("[data-subscription-summary]").textContent = `${state.subscriptions.length} repeating charge${state.subscriptions.length === 1 ? "" : "s"}`;
  }

  document.querySelector("[data-pass-points]").firstChild.textContent = String(state.coupons * 10);
  renderLeaderboard();
}

function renderLeaderboard() {
  const board = document.querySelector("[data-leaderboard]");
  board.replaceChildren();
  sampleLeaders.forEach((leader) => {
    const row = makeElement("div", "leader-row");
    leader.forEach((value) => row.append(makeElement("span", "", value)));
    board.append(row);
  });
  const userRow = makeElement("div", "leader-row you");
  userRow.append(
    makeElement("span", "", "16"),
    makeElement("span", "", state.showNickname ? "Beaza Guardian #190 · you" : "You"),
    makeElement("span", "", "♨ 0"),
    makeElement("span", "", "0"),
  );
  board.append(userRow);
}

const modalTemplates = {
  expense: '<h2 class="modal-title" id="modal-title">Add expense</h2><form class="modal-form" data-modal-form><label class="modal-field">Amount (BHD)<input name="amount" type="number" min="0.001" step="0.001" placeholder="0.000" required></label><label class="modal-field">Where (optional)<input name="description" maxlength="40" placeholder="e.g. Coffee shop"></label><label class="modal-field">Category<select name="category"><option>Bills</option><option>Food</option><option>Transport</option><option>Shopping</option><option>Other</option></select></label><div class="modal-actions"><button class="modal-button secondary" type="button" data-action="close-modal">Cancel</button><button class="modal-button" type="submit">Save</button></div></form>',
  limit: '<h2 class="modal-title" id="modal-title">Daily spending limit</h2><p class="modal-copy">Pick a daily guide that works for you.</p><form class="modal-form" data-modal-form><label class="modal-field">Daily limit (BHD)<input name="limit" type="number" min="0.001" step="0.001" placeholder="e.g. 5.000" required></label><button class="outline-action" type="button" data-action="income-calc">Work it out from my income</button><div class="modal-actions"><button class="modal-button secondary" type="button" data-action="close-modal">Cancel</button><button class="modal-button" type="submit">Save limit</button></div><p class="modal-feedback" data-modal-feedback></p></form>',
  income: '<h2 class="modal-title" id="modal-title">Work it out from income</h2><p class="modal-copy">A rough daily guide. Adjust it for your own essentials and plans.</p><form class="modal-form" data-modal-form><label class="modal-field">Monthly money available (BHD)<input name="income" type="number" min="0.001" step="0.001" placeholder="e.g. 150.000" required></label><label class="modal-field">Days to plan for<input name="days" type="number" min="1" max="31" value="30" required></label><p class="modal-feedback" data-income-result>Enter an amount to see a daily guide.</p><div class="modal-actions"><button class="modal-button secondary" type="button" data-action="close-modal">Cancel</button><button class="modal-button" type="submit">Use this guide</button></div></form>',
  quick: '<h2 class="modal-title" id="modal-title">Quick add</h2><p class="modal-copy">Say or type a purchase and amount, for example “karak 200 fils”.</p><form class="modal-form" data-modal-form><label class="modal-field">What did you spend?<input name="quick" placeholder="e.g. karak 200 fils" required></label><div class="voice-language" aria-label="Voice input language"><button type="button" class="selected" data-action="voice-language" data-language="en-GB">English</button><button type="button" data-action="voice-language" data-language="ar-BH">عربي</button></div><button class="voice-record-button" type="button" data-action="voice-listen"><svg class="app-icon"><use href="#icon-mic"></use></svg><span data-voice-label>Use voice</span></button><p class="voice-feedback" data-voice-feedback aria-live="polite">Your browser handles speech recognition and may use its own speech service.</p><div class="modal-actions"><button class="modal-button secondary" type="button" data-action="close-modal">Cancel</button><button class="modal-button" type="submit">Add expense</button></div><p class="modal-feedback" data-modal-feedback></p></form>',
  receipt: '<h2 class="modal-title" id="modal-title">Add a receipt</h2><p class="modal-copy">Take a photo or choose a receipt image. Enter the total manually to add it.</p><form class="modal-form" data-modal-form><input class="sr-only" name="receipt-camera" type="file" accept="image/*" capture="environment" tabindex="-1"><input class="sr-only" name="receipt-gallery" type="file" accept="image/*" tabindex="-1"><div class="receipt-actions"><button class="receipt-choice" type="button" data-action="receipt-camera"><svg class="app-icon"><use href="#icon-receipt"></use></svg><span>Take a photo</span></button><button class="receipt-choice secondary" type="button" data-action="receipt-gallery"><svg class="app-icon"><use href="#icon-picture"></use></svg><span>Choose a picture</span></button></div><figure class="receipt-preview" data-receipt-preview hidden><img alt="Selected receipt"><figcaption data-receipt-name></figcaption></figure><p class="modal-feedback" data-receipt-feedback aria-live="polite">Your image stays in this browser. The total is not read automatically.</p><div class="modal-actions"><button class="modal-button secondary" type="button" data-action="close-modal">Cancel</button><button class="modal-button" type="button" data-action="receipt-continue">Enter total</button></div></form>',
  goal: '<h2 class="modal-title" id="modal-title">Savings goal</h2><form class="modal-form" data-modal-form><label class="modal-field">What are you saving for?<input name="goal" maxlength="35" placeholder="e.g. New laptop" required></label><label class="modal-field">Goal amount (BHD)<input name="target" type="number" min="0.001" step="0.001" placeholder="e.g. 250.000" required></label><div class="modal-actions"><button class="modal-button secondary" type="button" data-action="close-modal">Cancel</button><button class="modal-button" type="submit">Save goal</button></div></form>',
  goalAdd: '<h2 class="modal-title" id="modal-title">Add money put aside</h2><form class="modal-form" data-modal-form><label class="modal-field">Amount (BHD)<input name="amount" type="number" min="0.001" step="0.001" placeholder="e.g. 2.000" required></label><div class="modal-actions"><button class="modal-button secondary" type="button" data-action="close-modal">Cancel</button><button class="modal-button" type="submit">Add to goal</button></div></form>',
  hold: '<h2 class="modal-title" id="modal-title">Put something on hold</h2><p class="modal-copy">Give an unplanned purchase 24 hours to think it over. This reminder cannot block a payment.</p><form class="modal-form" data-modal-form><label class="modal-field">What are you thinking of buying?<input name="name" maxlength="40" placeholder="e.g. New headphones" required></label><label class="modal-field">Price (BHD)<input name="amount" type="number" min="0.001" step="0.001" placeholder="e.g. 15.000" required></label><div class="modal-actions"><button class="modal-button secondary" type="button" data-action="close-modal">Cancel</button><button class="modal-button" type="submit">Start the 24-hour pause</button></div></form>',
  subscription: '<h2 class="modal-title" id="modal-title">Add a repeating charge</h2><form class="modal-form" data-modal-form><label class="modal-field">Shop or service<input name="name" maxlength="40" placeholder="e.g. Music app" required></label><label class="modal-field">Amount each month (BHD)<input name="amount" type="number" min="0.001" step="0.001" placeholder="e.g. 2.500" required></label><div class="modal-actions"><button class="modal-button secondary" type="button" data-action="close-modal">Cancel</button><button class="modal-button" type="submit">Save charge</button></div></form>',
  import: '<h2 class="modal-title" id="modal-title">Earlier messages</h2><p class="modal-copy">Earlier bank messages can be added in the Android app. This website cannot access messages or import them.</p><div class="import-notice" data-import-message></div><div class="modal-actions"><button class="modal-button secondary" type="button" data-action="close-modal">Not now</button><button class="modal-button" type="button" data-action="start-now">Start from now</button></div>',
  note: '<h2 class="modal-title" id="modal-title" data-note-title></h2><p class="modal-copy" data-note-copy></p><div class="modal-actions"><button class="modal-button" type="button" data-action="close-modal">Got it</button></div>',
};

function openModal(type, details = {}) {
  stopVoiceRecognition();
  releaseReceiptPreview();
  modalContent.innerHTML = modalTemplates[type];
  modalBackdrop.hidden = false;
  app.classList.add("modal-open");
  if (type === "limit") {
    const input = modalContent.querySelector('[name="limit"]');
    if (state.dailyLimit) input.value = state.dailyLimit.toFixed(3);
  }
  if (type === "income") {
    const input = modalContent.querySelector('[name="income"]');
    input.addEventListener("input", updateIncomeGuide);
    modalContent.querySelector('[name="days"]').addEventListener("input", updateIncomeGuide);
  }
  if (type === "import") {
    modalContent.querySelector("[data-import-message]").textContent =
      `Add up to ${details.days} days of earlier messages in the Android app.`;
  }
  if (type === "note") {
    modalContent.querySelector("[data-note-title]").textContent = details.title;
    modalContent.querySelector("[data-note-copy]").textContent = details.message;
  }
  if (type === "quick" || type === "expense") {
    const amountInput = modalContent.querySelector('[name="amount"]');
    if (details.amount) amountInput.value = details.amount;
    const descriptionInput = modalContent.querySelector('[name="description"]');
    if (details.description && descriptionInput) descriptionInput.value = details.description;
    if (details.description && modalContent.querySelector('[name="quick"]')) {
      modalContent.querySelector('[name="quick"]').value = details.description;
    }
  }
  if (type === "quick") updateVoiceLanguageButtons();
  if (type === "receipt") receiptHasImage = false;
  modalContent.querySelector(".modal-field input:not([type='file']), .modal-field select, .receipt-choice, button")?.focus();
}

function closeModal() {
  stopVoiceRecognition();
  releaseReceiptPreview();
  modalBackdrop.hidden = true;
  app.classList.remove("modal-open");
}

function releaseReceiptPreview() {
  if (receiptObjectUrl) {
    URL.revokeObjectURL(receiptObjectUrl);
    receiptObjectUrl = null;
  }
  receiptHasImage = false;
}

function updateVoiceLanguageButtons() {
  modalContent.querySelectorAll("[data-language]").forEach((button) => {
    button.classList.toggle("selected", button.dataset.language === voiceLanguage);
  });
}

function stopVoiceRecognition() {
  if (!voiceRecognition) return;
  const recognition = voiceRecognition;
  voiceRecognition = null;
  recognition.onend = null;
  recognition.onerror = null;
  recognition.onresult = null;
  try {
    recognition.stop();
  } catch (error) {
    console.warn("Speech recognition had already stopped:", error);
  }
}

function startVoiceRecognition(button) {
  const Recognition = window.SpeechRecognition || window.webkitSpeechRecognition;
  const feedback = modalContent.querySelector("[data-voice-feedback]");
  const label = modalContent.querySelector("[data-voice-label]");
  if (!Recognition) {
    feedback.textContent = "Voice input isn’t available in this browser. You can type your purchase and amount instead.";
    return;
  }

  stopVoiceRecognition();
  const recognition = new Recognition();
  voiceRecognition = recognition;
  recognition.lang = voiceLanguage;
  recognition.interimResults = false;
  recognition.maxAlternatives = 1;
  recognition.onstart = () => {
    button.classList.add("is-listening");
    button.setAttribute("aria-pressed", "true");
    label.textContent = "Listening… tap to stop";
    feedback.textContent = "Speak clearly, for example: “karak 200 fils”.";
  };
  recognition.onresult = (event) => {
    const transcript = event.results[0][0].transcript.trim();
    modalContent.querySelector('[name="quick"]').value = transcript;
    feedback.textContent = `Heard: “${transcript}”. Check the amount before adding.`;
  };
  recognition.onerror = (event) => {
    const messages = {
      "not-allowed": "Microphone access was blocked. Allow it in your browser, or type the expense instead.",
      "audio-capture": "No microphone was found. You can type the expense instead.",
      "no-speech": "No speech was heard. Try again or type the expense.",
      "network": "The browser’s speech service isn’t available. You can type the expense instead.",
    };
    feedback.textContent = messages[event.error] || "Voice input stopped. You can type the expense instead.";
  };
  recognition.onend = () => {
    button.classList.remove("is-listening");
    button.setAttribute("aria-pressed", "false");
    label.textContent = "Use voice";
    voiceRecognition = null;
  };

  try {
    recognition.start();
  } catch (error) {
    feedback.textContent = "Voice input couldn’t start. You can type the expense instead.";
    console.error("Speech recognition failed to start:", error);
    voiceRecognition = null;
  }
}

function updateIncomeGuide() {
  const income = Number(modalContent.querySelector('[name="income"]').value);
  const days = Number(modalContent.querySelector('[name="days"]').value);
  const output = modalContent.querySelector("[data-income-result]");
  output.textContent = income > 0 && days > 0
    ? `That’s about BHD ${formatAmount(income / days)} per day.`
    : "Enter an amount to see a daily guide.";
}

function addExpense(amount, description, category = "Other") {
  if (!Number.isFinite(amount) || amount <= 0) return false;
  state.expenses.push({
    amount: Math.round(amount * 1000) / 1000,
    description: description.trim() || category,
    category,
    time: new Intl.DateTimeFormat("en", { hour: "2-digit", minute: "2-digit", hour12: false }).format(new Date()),
  });
  renderToday();
  renderHistory();
  return true;
}

function showNote(title, message) {
  openModal("note", { title, message });
}

function handleAction(action, trigger) {
  switch (action) {
    case "expense":
      openModal("expense");
      break;
    case "limit":
      openModal("limit");
      break;
    case "income-calc":
      openModal("income");
      break;
    case "quick-add":
      openModal("quick");
      break;
    case "receipt":
      openModal("receipt");
      break;
    case "receipt-camera":
      modalContent.querySelector('[name="receipt-camera"]').click();
      break;
    case "receipt-gallery":
      modalContent.querySelector('[name="receipt-gallery"]').click();
      break;
    case "receipt-continue": {
      const description = receiptHasImage ? "Receipt purchase" : "";
      closeModal();
      openModal("expense", { description });
      break;
    }
    case "voice-language":
      voiceLanguage = trigger.dataset.language;
      updateVoiceLanguageButtons();
      break;
    case "voice-listen":
      if (voiceRecognition) {
        stopVoiceRecognition();
        const label = modalContent.querySelector("[data-voice-label]");
        const recordButton = modalContent.querySelector("[data-action='voice-listen']");
        recordButton?.classList.remove("is-listening");
        recordButton?.setAttribute("aria-pressed", "false");
        if (label) label.textContent = "Use voice";
      } else {
        startVoiceRecognition(trigger);
      }
      break;
    case "goal-set":
      openModal("goal");
      break;
    case "goal-add":
      openModal(state.goalTarget ? "goalAdd" : "goal");
      break;
    case "hold":
      openModal("hold");
      break;
    case "subscription":
      openModal("subscription");
      break;
    case "import":
      openModal("import", { days: trigger.dataset.days });
      break;
    case "start-now":
      state.importNotice = false;
      document.querySelector("[data-import-card]")?.remove();
      closeModal();
      break;
    case "settings":
      showNote("Settings", "Settings are available in the Android app.");
      break;
    case "ask":
      setScreen("ask");
      break;
    case "open-ask":
      closeModal();
      setScreen("ask");
      break;
    case "privacy":
      state.private = !state.private;
      app.classList.toggle("is-private", state.private);
      if (app.dataset.currentScreen === "history") renderHistory();
      if (state.private) {
        app.querySelectorAll("[data-money]").forEach((element) => element.classList.add("is-private"));
      } else {
        app.querySelectorAll("[data-money]").forEach((element) => element.classList.remove("is-private"));
      }
      trigger?.setAttribute("aria-label", state.private ? "Show balances" : "Hide balances");
      break;
    case "language":
      showNote("Language", "The Android app runs fully in Arabic (right to left) and English. This demo is in English only.");
      break;
    case "account":
      setScreen("account");
      break;
    case "account-info":
      showNote("Account", "Create an account or sign in from the Android app.");
      break;
    case "sort":
      state.historySorted = !state.historySorted;
      renderHistory();
      break;
    case "export":
      exportSampleData();
      break;
    case "coupon":
      state.coupons += 1;
      renderSaving();
      showNote("Sample coupon", "This is an example offer only. It isn’t a real coupon and no shop is connected.");
      break;
    case "offers-toggle":
      document.querySelector("[data-coupon-offers]").hidden = !trigger.checked;
      break;
    case "nickname-toggle":
      state.showNickname = trigger.checked;
      renderLeaderboard();
      break;
    case "challenge":
      showNote("Challenge", "Complete a challenge to build a streak and earn points.");
      break;
    case "ai-toggle":
      showNote("Smart answers", "Answers come from the expenses you enter. Nothing is sent to an AI service.");
      break;
    case "close-modal":
      closeModal();
      break;
    default:
      break;
  }
}

function exportSampleData() {
  const blob = new Blob([JSON.stringify({
    note: "Example expenses entered on this device.",
    dailyLimit: state.dailyLimit,
    expenses: state.expenses,
  }, null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = "beaza-expenses.json";
  link.click();
  window.setTimeout(() => URL.revokeObjectURL(url), 1000);
}

function answerQuestion(question) {
  const total = todayTotal();
  const lowered = question.toLowerCase();
  if (lowered.includes("left")) {
    if (state.dailyLimit) {
      return `BHD ${formatAmount(Math.max(state.dailyLimit - total, 0))} is left from your BHD ${formatAmount(state.dailyLimit)} daily limit.`;
    }
    return "Set a daily limit first and I can work out what’s left.";
  }
  if (lowered.includes("where") || lowered.includes("category")) {
    if (!state.expenses.length) return "There are no expenses yet. Add one and I’ll show where it went.";
    const categories = new Map();
    state.expenses.forEach((expense) => categories.set(expense.category, (categories.get(expense.category) || 0) + expense.amount));
    const details = [...categories].map(([category, amount]) => `${category}: BHD ${formatAmount(amount)}`).join("; ");
    return `Today’s spending is BHD ${formatAmount(total)}. ${details}.`;
  } else if (lowered.includes("tip")) {
    return state.dailyLimit && total >= state.dailyLimit * 0.8
      ? "You’re close to today’s limit. It may help to pause and check what you still need today."
      : "Try adding small purchases as they happen. A clearer picture can make the next choice easier.";
  }
  return `You’ve added BHD ${formatAmount(total)} today${state.dailyLimit ? `, from a BHD ${formatAmount(state.dailyLimit)} daily limit` : ""}.`;
}

function askQuestion(question) {
  const thread = document.querySelector("[data-chat-thread]");
  const userMessage = makeElement("p", "chat-bubble user-bubble", question.trim());
  const assistantMessage = makeElement("p", "chat-bubble assistant-bubble", answerQuestion(question));
  thread.append(userMessage, assistantMessage);
  assistantMessage.scrollIntoView({ block: "nearest", behavior: "smooth" });
}

document.querySelectorAll("[data-screen]").forEach((button) => {
  button.addEventListener("click", () => setScreen(button.dataset.screen));
});

app.addEventListener("click", (event) => {
  const button = event.target.closest("[data-action]");
  if (!button || !app.contains(button)) return;
  if (button.dataset.action === "limit" && event.target.closest(".income-link")) {
    openModal("income");
    return;
  }
  handleAction(button.dataset.action, button);
});

modalBackdrop.addEventListener("click", (event) => {
  if (event.target === modalBackdrop) closeModal();
});

document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && !modalBackdrop.hidden) closeModal();
});

modalContent.addEventListener("submit", (event) => {
  const form = event.target.closest("[data-modal-form]");
  if (!form) return;
  event.preventDefault();
  const data = new FormData(form);

  if (modalContent.querySelector('[name="amount"]') && modalContent.querySelector(".modal-title")?.textContent === "Add expense") {
    const amount = Number(data.get("amount"));
    if (!addExpense(amount, String(data.get("description") || ""), String(data.get("category") || "Other"))) {
      modalContent.querySelector(".modal-feedback").textContent = "Enter an amount above zero.";
      return;
    }
    closeModal();
    return;
  }

  const title = modalContent.querySelector(".modal-title")?.textContent;
  if (title === "Daily spending limit") {
    state.dailyLimit = Number(data.get("limit"));
    renderToday();
    closeModal();
  } else if (title === "Work it out from income") {
    const income = Number(data.get("income"));
    const days = Number(data.get("days"));
    if (income > 0 && days > 0) {
      state.dailyLimit = Math.round((income / days) * 1000) / 1000;
      renderToday();
      closeModal();
    }
  } else if (title === "Quick add") {
    const phrase = String(data.get("quick") || "").trim();
    const normalized = phrase
      .replace(/[٠-٩]/g, (digit) => String("٠١٢٣٤٥٦٧٨٩".indexOf(digit)))
      .replace(/[٫٬]/g, ".");
    const match = normalized.match(/(\d+(?:\.\d+)?)\s*(fils?|bd|bhd|فلس|دينار|دنانير|د\.?ب)?/i);
    if (!match) {
      modalContent.querySelector("[data-modal-feedback]").textContent = "Add an amount, such as “karak 200 fils” or “كرك ٢٠٠ فلس”.";
      return;
    }
    let amount = Number(match[1]);
    if (/^(fils?|فلس)$/i.test(match[2] || "")) amount /= 1000;
    const description = normalized.replace(match[0], "").trim();
    addExpense(amount, description || "Quick add");
    closeModal();
  } else if (title === "Savings goal") {
    state.goalName = String(data.get("goal") || "").trim();
    state.goalTarget = Number(data.get("target"));
    renderSaving();
    closeModal();
  } else if (title === "Add money put aside") {
    state.goalCurrent += Number(data.get("amount"));
    renderSaving();
    closeModal();
  } else if (title === "Put something on hold") {
    state.holds.push({ name: String(data.get("name") || "").trim(), amount: Number(data.get("amount")) });
    renderSaving();
    closeModal();
  } else if (title === "Add a repeating charge") {
    state.subscriptions.push({ name: String(data.get("name") || "").trim(), amount: Number(data.get("amount")) });
    renderSaving();
    closeModal();
  }
});

modalContent.addEventListener("change", (event) => {
  const input = event.target.closest('input[type="file"]');
  if (!input) return;
  const file = input.files[0];
  if (!file) return;
  if (!file.type.startsWith("image/")) {
    modalContent.querySelector("[data-receipt-feedback]").textContent = "Choose an image file to continue.";
    input.value = "";
    return;
  }
  if (receiptObjectUrl) URL.revokeObjectURL(receiptObjectUrl);
  receiptObjectUrl = URL.createObjectURL(file);
  receiptHasImage = true;
  const preview = modalContent.querySelector("[data-receipt-preview]");
  preview.querySelector("img").src = receiptObjectUrl;
  preview.hidden = false;
  modalContent.querySelector("[data-receipt-name]").textContent = file.name;
  modalContent.querySelector("[data-receipt-feedback]").textContent = "Image selected. Enter the total yourself; no receipt details are read automatically.";
});

document.querySelectorAll("[data-prompt]").forEach((button) => {
  button.addEventListener("click", () => askQuestion(button.dataset.prompt));
});

document.querySelector("[data-ask-form]").addEventListener("submit", (event) => {
  event.preventDefault();
  const data = new FormData(event.currentTarget);
  askQuestion(String(data.get("question") || ""));
  event.currentTarget.reset();
});



/* ---- demo starting data (example only) ---- */
(function seed() {
  const t = (h, m) => String(h).padStart(2, "0") + ":" + String(m).padStart(2, "0");
  state.dailyLimit = 5;
  state.expenses = [
    { amount: 0.8, description: "Coffee", category: "Food", time: t(9, 12) },
    { amount: 1.3, description: "Ride to campus", category: "Transport", time: t(8, 40) },
    { amount: 1.2, description: "Lunch", category: "Food", time: t(13, 5) },
  ];
  state.goalName = "New laptop";
  state.goalTarget = 300;
  state.goalCurrent = 45;
  state.holds = [{ name: "Wireless earbuds", amount: 18 }];
  state.importNotice = false;
  document.querySelector("[data-import-card]")?.remove();
})();
app.dataset.currentScreen = "today";
renderToday();
renderHistory();
renderSaving();
