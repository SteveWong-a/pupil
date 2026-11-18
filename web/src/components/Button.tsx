import type { MouseEventHandler, ReactNode } from "react";
import styles from "./Button.module.css";

interface ButtonProps {
  href?: string;
  small?: boolean;
  ghost?: boolean;
  onClick?: MouseEventHandler<HTMLAnchorElement>;
  children: ReactNode;
}

export function Button({ href = "#", small, ghost, onClick, children }: ButtonProps) {
  const cls = [styles.button, small && styles.small, ghost && styles.ghost].filter(Boolean).join(" ");
  return (
    <a href={href} className={cls} onClick={onClick}>
      {children}
    </a>
  );
}
