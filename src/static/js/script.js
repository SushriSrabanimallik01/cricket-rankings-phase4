/**
 * script.js - Frontend interactions and validation for ICC Cricket Rankings
 */

document.addEventListener("DOMContentLoaded", function () {
  // 1. Auto-dismiss flash alerts after 6 seconds
  const alerts = document.querySelectorAll(".alert");
  alerts.forEach(function (alert) {
    const closeBtn = alert.querySelector(".alert-close");
    if (closeBtn) {
      closeBtn.addEventListener("click", function () {
        alert.style.display = "none";
      });
    }
    setTimeout(function () {
      alert.style.transition = "opacity 0.5s ease";
      alert.style.opacity = "0";
      setTimeout(function () {
        alert.remove();
      }, 500);
    }, 6000);
  });

  // 2. Form validation for Add Match (I1)
  const addMatchForm = document.getElementById("form-add-match");
  if (addMatchForm) {
    addMatchForm.addEventListener("submit", function (e) {
      const team1 = document.getElementById("match-team1")?.value;
      const team2 = document.getElementById("match-team2")?.value;
      const startDate = document.getElementById("match-start-date")?.value;
      const endDate = document.getElementById("match-end-date")?.value;

      if (team1 && team2 && team1 === team2) {
        e.preventDefault();
        alert("Constraint C6: A match must have two different teams!");
        return false;
      }

      if (startDate && endDate && endDate < startDate) {
        e.preventDefault();
        alert("Constraint C4: Match end date cannot be earlier than start date!");
        return false;
      }
    });
  }

  // 3. Form validation for Result Recording (U1)
  const resultSelect = document.getElementById("select-result");
  const winFields = document.getElementById("win-specific-fields");
  if (resultSelect && winFields) {
    function toggleWinFields() {
      if (resultSelect.value === "Win") {
        winFields.style.display = "block";
      } else {
        winFields.style.display = "none";
      }
    }
    resultSelect.addEventListener("change", toggleWinFields);
    toggleWinFields();
  }

  // 4. Dynamic Snapshot Row Adding (I2)
  const addRowBtn = document.getElementById("btn-add-snapshot-row");
  const snapshotTableBody = document.getElementById("snapshot-rows-body");
  if (addRowBtn && snapshotTableBody) {
    addRowBtn.addEventListener("click", function () {
      const firstRow = snapshotTableBody.querySelector("tr");
      if (firstRow) {
        const newRow = firstRow.cloneNode(true);
        // Clear input values
        newRow.querySelectorAll("input").forEach(function (inp) {
          inp.value = "";
        });
        snapshotTableBody.appendChild(newRow);
      }
    });
  }

  // 5. Deletion confirmations (D1, D2)
  const deleteForms = document.querySelectorAll(".form-confirm-delete");
  deleteForms.forEach(function (form) {
    form.addEventListener("submit", function (e) {
      const confirmMsg = form.getAttribute("data-confirm") || "Are you sure you want to delete this record? This action cannot be undone.";
      if (!confirm(confirmMsg)) {
        e.preventDefault();
        return false;
      }
    });
  });
});
