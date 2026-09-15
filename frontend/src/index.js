import React from "react";
import ReactDOM from "react-dom/client";
import "@/index.css";
import App from "@/App";

document.documentElement.lang = "ar";
document.documentElement.dir = "rtl";

const root = ReactDOM.createRoot(document.getElementById("root"));
root.render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
