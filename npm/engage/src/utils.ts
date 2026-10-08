export const generateId = () => {
  const uuid =
    Math.random().toString(36).substring(2, 15) +
    Math.random().toString(36).substring(2, 15);

  if (
    typeof window === "undefined" ||
    typeof window.localStorage === "undefined"
  ) {
    return uuid;
  }

  let uuidFromLocalStorage = localStorage.getItem("lowco_uuid");
  if (!uuidFromLocalStorage) {
    uuidFromLocalStorage = uuid;
    localStorage.setItem("lowco_uuid", uuidFromLocalStorage);
  }
  return uuidFromLocalStorage;
};
