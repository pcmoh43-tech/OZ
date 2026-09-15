import { splitForHostDisplay } from "@/lib/writing-direction";

function HostText({ text, as: Component = "span", className, ...props }) {
  const parts = splitForHostDisplay(text);

  return (
    <Component dir="rtl" className={className} {...props}>
      {parts.map((part, index) =>
        part.kind === "latin" ? (
          <span key={index} dir="ltr" className="embedded-ltr">
            {part.value}
          </span>
        ) : (
          <span key={index}>{part.value}</span>
        )
      )}
    </Component>
  );
}

export default HostText;
