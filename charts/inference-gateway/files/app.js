"use strict";

(function () {
  var form = document.getElementById("chat-form");
  var input = document.getElementById("message");
  var conversation = document.getElementById("conversation");
  var emptyState = document.getElementById("empty-state");
  var sendButton = document.getElementById("send-button");
  var stopButton = document.getElementById("stop-button");
  var requestStatus = document.getElementById("request-status");
  var healthDot = document.getElementById("health-dot");
  var healthText = document.getElementById("health-text");
  var modelMeta = document.querySelector('meta[name="edge-llm-model"]');
  var modelId = modelMeta.content;
  var messages = [];
  var activeController = null;

  function setHealth(ok, label) {
    healthDot.classList.toggle("ok", ok);
    healthDot.classList.toggle("bad", !ok);
    healthText.textContent = label;
  }

  async function checkHealth() {
    try {
      var response = await fetch("/health", {
        method: "GET",
        headers: { Accept: "application/json" },
        cache: "no-store"
      });
      if (!response.ok) {
        throw new Error("HTTP " + response.status);
      }
      var payload = await response.json();
      setHealth(payload.status === "ok", payload.status === "ok" ? "利用可能" : "利用不可");
    } catch (_error) {
      setHealth(false, "利用不可");
    }
  }

  function addMessage(role, content) {
    if (emptyState) {
      emptyState.remove();
      emptyState = null;
    }

    var article = document.createElement("article");
    article.className = "message " + role;
    var label = document.createElement("span");
    label.className = "message-label";
    label.textContent = role === "user" ? "You" : "Model";
    var body = document.createElement("div");
    body.className = "message-body";
    body.textContent = content;
    article.appendChild(label);
    article.appendChild(body);
    conversation.appendChild(article);
    conversation.scrollTop = conversation.scrollHeight;
    return body;
  }

  function setBusy(busy) {
    input.disabled = busy;
    sendButton.disabled = busy;
    stopButton.hidden = !busy;
    requestStatus.textContent = busy ? "生成中" : "";
  }

  function parseEvent(eventText, assistantBody, state) {
    var lines = eventText.split("\n");
    for (var index = 0; index < lines.length; index += 1) {
      if (lines[index].indexOf("data:") !== 0) {
        continue;
      }
      var data = lines[index].slice(5).trimStart();
      if (!data) {
        continue;
      }
      if (data === "[DONE]") {
        state.done = true;
        continue;
      }

      var frame = JSON.parse(data);
      var choice = frame.choices && frame.choices[0];
      var delta = choice && choice.delta;
      if (delta && typeof delta.reasoning_content === "string") {
        state.reasoning += delta.reasoning_content;
        if (!state.content) {
          assistantBody.textContent = state.reasoning;
          conversation.scrollTop = conversation.scrollHeight;
        }
      }
      if (delta && typeof delta.content === "string") {
        state.content += delta.content;
        assistantBody.textContent = state.content;
        conversation.scrollTop = conversation.scrollHeight;
      }
    }
  }

  async function streamChat(userContent) {
    activeController = new AbortController();
    setBusy(true);
    var assistantBody = addMessage("assistant", "");
    var state = { content: "", reasoning: "", done: false };
    var requestMessages = messages.concat([
      { role: "user", content: userContent }
    ]);

    try {
      var response = await fetch("/v1/chat/completions", {
        method: "POST",
        headers: {
          Accept: "text/event-stream",
          "Content-Type": "application/json"
        },
        body: JSON.stringify({
          model: modelId,
          messages: requestMessages,
          max_tokens: 512,
          stream: true
        }),
        signal: activeController.signal
      });

      if (!response.ok) {
        var errorText = await response.text();
        throw new Error("HTTP " + response.status + (errorText ? ": " + errorText : ""));
      }
      if (!response.body) {
        throw new Error("streaming response body is unavailable");
      }

      var reader = response.body.getReader();
      var decoder = new TextDecoder();
      var pending = "";

      while (!state.done) {
        var result = await reader.read();
        pending += decoder.decode(result.value || new Uint8Array(), { stream: !result.done });
        var events = pending.split(/\r?\n\r?\n/);
        pending = events.pop() || "";
        for (var index = 0; index < events.length; index += 1) {
          parseEvent(events[index], assistantBody, state);
        }
        if (result.done) {
          if (pending.trim()) {
            parseEvent(pending, assistantBody, state);
          }
          break;
        }
      }

      if (!state.done) {
        throw new Error("stream ended before terminal [DONE]");
      }

      var displayContent = state.content || state.reasoning;
      if (!displayContent.trim()) {
        throw new Error("model returned no displayable content");
      }
      assistantBody.textContent = displayContent;
      messages = requestMessages.concat([
        { role: "assistant", content: displayContent }
      ]);
    } catch (error) {
      if (error.name === "AbortError") {
        var partialContent = state.content || state.reasoning;
        assistantBody.textContent = partialContent
          ? partialContent + "\n\n（生成を停止しました）"
          : "生成を停止しました。";
        requestStatus.textContent = "停止しました";
      } else {
        assistantBody.textContent = "リクエストに失敗しました。時間を置いて再試行してください。";
        requestStatus.textContent = "送信失敗";
      }
    } finally {
      activeController = null;
      setBusy(false);
      input.focus();
      checkHealth();
    }
  }

  form.addEventListener("submit", function (event) {
    event.preventDefault();
    var content = input.value.trim();
    if (!content || activeController) {
      return;
    }
    addMessage("user", content);
    input.value = "";
    streamChat(content);
  });

  input.addEventListener("keydown", function (event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault();
      form.requestSubmit();
    }
  });

  stopButton.addEventListener("click", function () {
    if (activeController) {
      activeController.abort();
    }
  });

  checkHealth();
  window.setInterval(checkHealth, 30000);
})();
